# shellcheck shell=bash
# Session lifecycle: locking, all-or-nothing start, resync that never changes
# structure, unsync failures, and the recover verb run by ExecStopPost.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }
P_B() { echo "$XDG_CONFIG_HOME/psdtest-b"; }
TMP_A() { echo "$XDG_RUNTIME_DIR/psd/$(id -un)-psdtest-a"; }

# stub_cmd <name> <pattern>: make <name> fail when its arguments match the
# glob <pattern>, otherwise run it through the normal shim
stub_cmd() {
  mkdir -p "$T/shim2"
  ln -sf "$T_SRC/test/shim" "$T/shim2/$1"
  cat > "$T/bin/$1" <<EOS
#!/bin/bash
case "\$*" in $2) exit 1 ;; esac
PATH=\${PATH#"$T_SHIMS:"}
exec "$T/shim2/$1" "\$@"
EOS
  chmod 755 "$T/bin/$1"
  ln -sf "$T/bin/$1" "$T_SHIMS/$1"
}

unstub_cmd() {
  ln -sf "$T_SRC/test/shim" "$T_SHIMS/$1"
}

test_lock_not_held_by_fuse_daemons() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  if ! flock -n "$XDG_RUNTIME_DIR/psd.lock" true; then
    fail "the lock is still held after start (inherited by a daemon)"
    kill_fake_daemons
  fi
  assert_ok psd unsync
}

test_resync_skips_while_locked() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  flock -w 10 "$XDG_RUNTIME_DIR/psd.lock" sleep 3 &
  sleep 0.3
  export PSD_TRACE=$T/trace
  assert_ok psd resync
  grep -qs '^rsync ' "$PSD_TRACE" && fail "resync ran while another run held the lock"
  wait
  assert_ok psd unsync
  assert_version "$P" v2
}

test_unsync_waits_for_lock() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  flock -w 10 "$XDG_RUNTIME_DIR/psd.lock" sleep 2 &
  sleep 0.3
  local t0=$SECONDS
  assert_ok psd unsync
  (( SECONDS - t0 >= 1 )) || fail "unsync did not wait for the lock"
  wait
  assert_version "$P" v2
}

test_failed_start_rolls_back_every_profile() {
  write_conf 'BROWSERS=(psdtest-a psdtest-b)'
  local A B
  A=$(P_A) B=$(P_B)
  profile_new "$A" a1
  profile_new "$B" b1
  stub_cmd fuse-overlayfs '*psdtest-b*'
  assert_fails start_session
  assert_realdir "$A"
  assert_realdir "$B"
  assert_version "$A" a1
  assert_version "$B" b1
  assert_absent "$A-backup"
  assert_absent "$B-backup"
  assert_absent "$XDG_RUNTIME_DIR/psd.pid"
  assert_absent "$(TMP_A)"
  unstub_cmd fuse-overlayfs
  assert_ok start_session
  assert_symlink "$A"
  assert_ok psd unsync
}

test_new_profile_mid_session_not_adopted() {
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  echo "$M/one" > "$M/profiles"
  assert_ok start_session
  # a profile created while psd runs, e.g. in the browser's profile manager
  profile_new "$M/two" two1
  echo "$M/two" >> "$M/profiles"
  assert_ok psd resync
  assert_realdir "$M/two"
  assert_absent "$M/two-backup"
  assert_ok psd unsync
  assert_version "$M/two" two1
  assert_ok start_session
  assert_symlink "$M/two"
  assert_ok psd unsync
}

test_colliding_profile_mid_session_not_adopted() {
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one/default" one1
  echo "$M/one/default" > "$M/profiles"
  assert_ok start_session
  # same last directory as the synced profile
  profile_new "$M/two/default" two1
  echo "$M/two/default" >> "$M/profiles"
  assert_ok psd resync
  assert_realdir "$M/two/default"
  assert_version "$M/two/default" two1
  assert_ok psd unsync
  assert_version "$M/one/default" one1
  assert_version "$M/two/default" two1
}

test_unsync_copy_failure_keeps_session() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  # the copy from tmpfs fails, e.g. disk full
  stub_cmd rsync "*/psd/*"
  assert_fails psd unsync
  assert_symlink "$P"
  assert_version "$P" v2
  [[ -f "$XDG_RUNTIME_DIR/psd.pid" ]] || fail "PID removed although unsync failed"
  unstub_cmd rsync
  assert_ok psd unsync
  assert_realdir "$P"
  assert_version "$P" v2
}

test_recover_after_clean_stop_does_nothing() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd unsync
  local before
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_ok psd recover
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
}

test_recover_refuses_live_session() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  local before
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_fails psd recover
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
  assert_ok psd unsync
}

test_recover_after_failed_stop() {
  # unsync fails, systemd kills the fuse daemons, then ExecStopPost runs
  xfail "bug 5: the failed copy already removed the last good marker" "recovered 'v1'"
  local P v; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  stub_cmd rsync "*/psd/*"
  assert_fails psd unsync
  unstub_cmd rsync
  kill_daemons
  assert_ok psd recover
  assert_realdir "$P"
  v=$(profile_version "$P")
  [[ "$v" == v2 || "$v" == v3 ]] || fail "recovered '$v', expected v2 or newer"
  assert_absent "$XDG_RUNTIME_DIR/psd.pid"
  assert_ok start_session
  assert_ok psd unsync
}

test_kill_during_start_then_recover() {
  # the start is killed (e.g. TimeoutStartSec), systemd kills the fuse
  # daemons and runs ExecStopPost, all in the same boot
  local P n=1 hit
  P=$(P_A)
  while (( n < 100 )); do
    unmount_all
    rm -rf "$P" "$P"-* "$XDG_CONFIG_HOME/psd/.psd.conf"
    reboot_sim
    profile_new "$P" v1
    rm -f "$PSD_SHIM_COUNT"
    PSD_FAULT=$n:kill start_session
    hit=$?
    kill_daemons
    psd recover || fail "kill before call $n: recover failed"
    assert_version "$P" v1
    if start_session && profile_write "$P" next && psd unsync; then
      assert_version "$P" next
    else
      fail "kill before call $n: next session failed"
    fi
    (( hit == 137 || hit == 9 )) || break
    n=$(( n + 1 ))
  done
}

test_recover_after_killed_session_with_link() {
  # the fuse daemon died and left its empty mountpoint; the link to it is
  # psd's own, not a user's symlinked profile
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  kill_daemons
  assert_ok psd recover
  assert_realdir "$P"
  assert_version "$P" v1
  assert_absent "$(TMP_A)"
  assert_ok start_session
  assert_ok psd unsync
}

test_browser_recreating_profile_during_start() {
  # a browser started at login recreates the profile dir right after psd
  # moved it away; the start must fail and undo, not link inside it
  local P; P=$(P_A)
  profile_new "$P" v1
  mkdir -p "$T/shim2"
  ln -sf "$T_SRC/test/shim" "$T/shim2/fuse-overlayfs"
  cat > "$T/bin/fuse-overlayfs" <<EOS
#!/bin/bash
PATH=\${PATH#"$T_SHIMS:"}
"$T/shim2/fuse-overlayfs" "\$@" || exit
mkdir -p "$P"
EOS
  chmod 755 "$T/bin/fuse-overlayfs"
  ln -sf "$T/bin/fuse-overlayfs" "$T_SHIMS/fuse-overlayfs"
  assert_fails start_session
  assert_absent "$XDG_RUNTIME_DIR/psd.pid"
  [[ -e "$P/.flagged" || -h "$P/psdtest-a" ]] && fail "linked inside the recreated dir"
  unstub_cmd fuse-overlayfs
  assert_ok psd recover
  assert_version "$P" v1
}

test_stale_upper_moved_aside() {
  # writes a dead session left in tmpfs must not be layered over the profile
  local P U; P=$(P_A)
  U=$XDG_RUNTIME_DIR/psd/$(id -un)-psdtest-a-rw
  profile_new "$P" v1
  mkdir -p "$U"
  echo old > "$U/prefs.js"
  assert_ok start_session
  [[ -e "$U/prefs.js" ]] && fail "stale upper reused"
  compgen -G "$XDG_RUNTIME_DIR/psd/.stale-$(id -un)-psdtest-a-rw-*/prefs.js" >/dev/null ||
    fail "stale upper not kept"
  assert_ok psd unsync
  assert_version "$P" v1
}

test_unsync_restore_failure_keeps_pid() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  stub_cmd mv "*-backup */psdtest-a"
  assert_fails psd unsync
  unstub_cmd mv
  [[ -f "$XDG_RUNTIME_DIR/psd.pid" ]] || fail "PID removed although the restore failed"
  assert_ok psd recover
  assert_version "$P" v2
}

test_live_mount_without_flag_left_alone() {
  # the newest data is only in the live mount; never fall back to disk
  local P before; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  rm -f "$P/.flagged" "$XDG_RUNTIME_DIR/psd.pid"
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_fails psd startup
  assert_fails psd recover
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
  assert_symlink "$P"
  assert_version "$P" v2
}
