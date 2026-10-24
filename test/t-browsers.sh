# shellcheck shell=bash
# Running browsers: detection, a clean shutdown before unsync, and processes
# that still use a profile.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }

# fake_browser <name> <profile> <seconds>: a process named <name> that, when
# asked to quit, takes <seconds> to write a last file into <profile>
fake_browser() {
  cat > "$T_BIN/$1" <<EOS
#!/bin/bash
trap 'sleep $3; echo saved > "$2/saved-on-exit"; exit 0' TERM
while :; do sleep 0.1; done
EOS
  chmod 755 "$T_BIN/$1"
  "$T_BIN/$1" &
  FAKE_PID=$!
  sleep 0.3
}

test_browser_gets_time_to_save() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  fake_browser psdtst-a "$P" 1
  assert_ok psd unsync
  assert_realdir "$P"
  [[ -e "$P/saved-on-exit" ]] || fail "the browser was killed before it saved"
  kill "$FAKE_PID" 2>/dev/null
  wait "$FAKE_PID" 2>/dev/null
}

test_long_process_name_detected() {
  write_conf 'BROWSERS=(psdtest-long)'
  local P=$XDG_CONFIG_HOME/psdtest-long
  profile_new "$P" v1
  fake_browser psdtst-long-browser-name "$P" 0
  assert_fails psd startup
  grep -q 'Refusing to start' "$T_LOG" || fail "running browser not detected"
  kill "$FAKE_PID" 2>/dev/null
  wait "$FAKE_PID" 2>/dev/null
  assert_ok start_session
  fake_browser psdtst-long-browser-name "$P" 1
  assert_ok psd unsync
  [[ -e "$P/saved-on-exit" ]] || fail "the browser was not stopped before unsync"
  kill "$FAKE_PID" 2>/dev/null
  wait "$FAKE_PID" 2>/dev/null
}

test_holders_are_named() {
  local P pid; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  (cd "$P" && exec sleep 30) &
  pid=$!
  sleep 0.2
  assert_ok psd unsync
  grep -q "still in use by: $pid (sleep)" "$T_LOG" || fail "holder not reported"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

# fake_df <percent used>
fake_df() {
  printf '#!/bin/sh\necho Use%%; echo %s%%\n' "$1" > "$T_BIN/df"
  chmod 755 "$T_BIN/df"
  ln -sf "$T_BIN/df" "$T_SHIMS/df"
}

test_full_runtime_dir_warned() {
  local P; P=$(P_A)
  profile_new "$P" v1
  fake_df 95
  assert_ok start_session
  assert_ok psd resync
  grep -q '95% full' "$T_LOG" || fail "no warning about the full runtime dir"
  assert_ok psd unsync
  assert_version "$P" v1
}

# fake_suspend_helper: an inhibit helper with a child, like the real one
# with its systemd-inhibit
fake_suspend_helper() {
  printf '#!/bin/bash\nsleep 300 &\nwait\n' > "$T_BIN/psd-suspend-sync"
  chmod 755 "$T_BIN/psd-suspend-sync"
}

test_suspend_helper_stopped_as_a_group() {
  local P pgid; P=$(P_A)
  profile_new "$P" v1
  write_conf 'BROWSERS=(psdtest-a)' 'USE_SUSPSYNC="yes"'
  fake_suspend_helper
  assert_ok start_session
  sleep 0.3
  pgid=$(cat "$XDG_RUNTIME_DIR/psd-suspend-sync.pid" 2>/dev/null)
  if [[ -z "$pgid" ]] || ! pgrep -g "$pgid" >/dev/null; then
    fail "helper not running"
    return
  fi
  assert_ok psd recycle-inhibit-lock
  sleep 0.3
  pgrep -g "$pgid" >/dev/null && fail "old helper group left running"
  pgid=$(cat "$XDG_RUNTIME_DIR/psd-suspend-sync.pid" 2>/dev/null)
  if [[ -z "$pgid" ]] || ! pgrep -g "$pgid" >/dev/null; then
    fail "no new helper"
  fi
  assert_ok psd unsync
  sleep 0.3
  pgrep -g "$pgid" >/dev/null && fail "helper group left running after unsync"
  assert_absent "$XDG_RUNTIME_DIR/psd-suspend-sync.pid"
}

test_roomy_runtime_dir_not_warned() {
  local P; P=$(P_A)
  profile_new "$P" v1
  fake_df 20
  assert_ok start_session
  assert_ok psd resync
  grep -q '% full' "$T_LOG" && fail "warned although there is room"
  assert_ok psd unsync
}

test_browser_ignoring_term_is_killed_in_time() {
  local P t0; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  cat > "$T_BIN/psdtst-a" <<'EOS'
#!/bin/bash
trap '' TERM
while :; do sleep 0.1; done
EOS
  chmod 755 "$T_BIN/psdtst-a"
  "$T_BIN/psdtst-a" &
  FAKE_PID=$!
  sleep 0.3
  t0=$SECONDS
  assert_ok psd unsync
  (( SECONDS - t0 <= 20 )) || fail "took $(( SECONDS - t0 ))s to kill the browser"
  grep -q 'did not quit within 10 seconds' "$T_LOG" || fail "no warning before the kill"
  kill -0 "$FAKE_PID" 2>/dev/null && fail "browser still running"
  wait "$FAKE_PID" 2>/dev/null
  assert_version "$P" v1
}

test_quitting_browser_not_signalled() {
  # at logout the session TERMs the browser while psd stops; a second TERM
  # would cut its shutdown short
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  cat > "$T_BIN/psdtst-a" <<EOS
#!/bin/bash
trap 'echo signalled > "$P/got-term"; exit 1' TERM
sleep 1.5 & wait
echo saved > "$P/saved-on-exit"
EOS
  chmod 755 "$T_BIN/psdtst-a"
  "$T_BIN/psdtst-a" &
  FAKE_PID=$!
  sleep 0.2
  assert_ok psd unsync
  wait "$FAKE_PID" 2>/dev/null
  assert_absent "$P/got-term"
  [[ -e "$P/saved-on-exit" ]] || fail "the quitting browser did not finish"
}

test_zombie_browser_not_waited_for() {
  local P t0; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  printf '#!/bin/sh\nexit 0\n' > "$T_BIN/psdtst-a"
  chmod 755 "$T_BIN/psdtst-a"
  # the parent never reaps its exited child
  ( "$T_BIN/psdtst-a" & exec sleep 8 ) &
  FAKE_PID=$!
  sleep 0.5
  t0=$SECONDS
  assert_ok psd unsync
  (( SECONDS - t0 <= 2 )) || fail "waited $(( SECONDS - t0 ))s for a zombie"
  kill "$FAKE_PID" 2>/dev/null
  wait "$FAKE_PID" 2>/dev/null
}

test_holders_scan_does_not_report_itself() {
  # the shells that cd'd into the profile are real holders, the scan is not
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  (cd "$P" && psd unsync 2>/dev/null) || fail "unsync failed"
  grep -E 'still in use by' "$T_LOG" | grep -qE '\(find\)|[0-9]+ \(\)' &&
    fail "the scan reported itself"
  assert_version "$P" v1
}

test_startup_after_stale_pid_uses_live_config() {
  # the session was started without suspend sync; the config now has it
  local P pgid; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  stub_cmd rsync '*-back-ovfs.new/'
  assert_fails psd unsync
  unstub_cmd rsync
  kill_daemons
  write_conf 'BROWSERS=(psdtest-a)' 'USE_SUSPSYNC="yes"'
  fake_suspend_helper
  assert_ok start_session
  sleep 0.3
  pgid=$(cat "$XDG_RUNTIME_DIR/psd-suspend-sync.pid" 2>/dev/null)
  if [[ -z "$pgid" ]] || ! pgrep -g "$pgid" >/dev/null; then
    fail "the restart used the old session's config"
  fi
  assert_ok psd unsync
  assert_version "$P" v2
}

test_manual_startup_of_live_session_refused_quietly() {
  local P before; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_fails psd startup
  grep -q 'not stopped cleanly' "$T_LOG" && fail "claimed to recover a live session"
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
  assert_ok psd unsync
}
