# shellcheck shell=bash
# Session lifecycle: locking, all-or-nothing start, resync that never changes
# structure, unsync failures, and the recover verb run by ExecStopPost.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }
P_B() { echo "$XDG_CONFIG_HOME/psdtest-b"; }
TMP_A() { echo "$XDG_RUNTIME_DIR/psd/$(id -un)-psdtest-a"; }

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
  cat > "$T_BIN/fuse-overlayfs" <<EOS
#!/bin/bash
PATH=\${PATH#"$T_SHIMS:"}
"$T/shim2/fuse-overlayfs" "\$@" || exit
mkdir -p "$P"
EOS
  chmod 755 "$T_BIN/fuse-overlayfs"
  ln -sf "$T_BIN/fuse-overlayfs" "$T_SHIMS/fuse-overlayfs"
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

test_profile_dropped_from_config_mid_session() {
  # profiles.ini edited or a browser removed from BROWSERS while psd runs;
  # the session still owns the profile until it is back on disk
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  profile_new "$M/two" two1
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok start_session
  profile_write "$M/two" two2
  echo "$M/one" > "$M/profiles"
  assert_ok psd unsync
  assert_realdir "$M/two"
  assert_version "$M/two" two2
  assert_absent "$XDG_CONFIG_HOME/psd/.psd-session"
}

test_crash_recovers_profile_dropped_from_config() {
  write_conf 'BROWSERS=(psdtest-a psdtest-b)'
  local A B
  A=$(P_A) B=$(P_B)
  profile_new "$A" a1
  profile_new "$B" b1
  assert_ok start_session
  profile_write "$B" b2
  assert_ok psd resync
  reboot_sim
  write_conf 'BROWSERS=(psdtest-a)'
  assert_ok psd startup
  assert_realdir "$B"
  assert_version "$B" b2
  assert_absent "$XDG_CONFIG_HOME/psd/.psd-session"
}

test_unsync_with_dead_mount_keeps_newest() {
  # the fuse daemon died (OOM, oomd) while the session went on
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  kill_daemons
  assert_ok psd unsync
  assert_realdir "$P"
  assert_version "$P" v3
  assert_absent "$XDG_RUNTIME_DIR/psd.pid"
  assert_ok start_session
  assert_ok psd unsync
  assert_version "$P" v3
}

test_kill_during_replay() {
  # recover is killed (TimeoutStopSec) while copying a dead mount's writes;
  # systemd kills its fuse daemon too, and the next run must still get them
  local P n=1 hit
  P=$(P_A)
  while (( n < 200 )); do
    unmount_all
    rm -rf "$P" "$P"-* "$XDG_CONFIG_HOME/psd/.psd.conf" "$XDG_CONFIG_HOME/psd/.psd-session"
    reboot_sim
    profile_new "$P" v1
    if ! { start_session && profile_write "$P" v2 && psd resync; }; then
      fail "setup failed"
      return
    fi
    profile_write "$P" v3
    kill_daemons
    rm -f "$PSD_SHIM_COUNT"
    PSD_FAULT=$n:kill psd recover
    hit=$?
    kill_daemons
    psd recover || fail "kill before call $n: second recover failed"
    assert_version "$P" v3
    (( hit == 137 || hit == 9 )) || break
    n=$(( n + 1 ))
  done
  (( n > 1 )) || fail "fault never triggered"
}

test_legacy_session_stamped_after_resync() {
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  grep -qx PSD_SESSION_MARKERS=1 "$XDG_CONFIG_HOME/psd/.psd.conf" &&
    { skip "the release already stamps sessions"; return; }
  profile_write "$P" v2
  assert_ok psd resync
  grep -qx PSD_SESSION_MARKERS=1 "$XDG_CONFIG_HOME/psd/.psd.conf" ||
    fail "legacy session not stamped after a marked resync"
  assert_ok psd unsync
  assert_version "$P" v2
}

test_leftover_session_file_after_older_unsync() {
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd_with "$BASE" unsync
  assert_version "$P" v2
  # the older psd does not know the session file
  assert_ok start_session
  profile_write "$P" v3
  assert_ok psd unsync
  assert_version "$P" v3
  assert_absent "$XDG_CONFIG_HOME/psd/.psd-session"
}

# setup_dead_mount <dir>: v2 on disk from the last resync, v3 written since,
# then the fuse daemon dies
setup_dead_mount() {
  unmount_all
  rm -rf "$1" "$1"-* "$XDG_CONFIG_HOME/psd/.psd.conf" "$XDG_CONFIG_HOME/psd/.psd-session"
  reboot_sim
  profile_new "$1" v1
  if ! { start_session && profile_write "$1" v2 && psd resync; }; then
    return 1
  fi
  profile_write "$1" v3
  kill_daemons
  rm -f "$PSD_SHIM_COUNT"
}

test_kill_during_replay_then_reboot() {
  # recover is cut off by the stop timeout and the machine powers off; the
  # last hourly copy must still be there
  local P n=1 hit v
  P=$(P_A)
  while (( n < 200 )); do
    setup_dead_mount "$P" || { fail "setup failed"; return; }
    PSD_FAULT=$n:kill psd recover
    hit=$?
    reboot_sim
    psd startup || fail "kill before call $n: startup failed"
    v=$(profile_version "$P")
    [[ "$v" == v2 || "$v" == v3 ]] || fail "kill before call $n, reboot: recovered '$v'"
    (( hit == 137 || hit == 9 )) || break
    n=$(( n + 1 ))
  done
  (( n > 1 )) || fail "fault never triggered"
}

test_upper_never_deleted_in_place() {
  # a delete cut short would leave a partial UPPER that the next recovery
  # replays over BACKUP
  local P; P=$(P_A)
  setup_dead_mount "$P" || { fail "setup failed"; return; }
  export PSD_TRACE=$T/trace
  assert_ok psd recover
  assert_ok start_session
  assert_ok psd unsync
  grep -E '^rm .*-rw( |$)' "$PSD_TRACE" && fail "an upper dir was deleted in place"
  assert_version "$P" v3
}

test_stale_session_file_with_older_session() {
  # an older psd ended a session of ours and started its own with another
  # profile set; the file it left is not that session's
  build_base release || return
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  profile_new "$M/two" two1
  echo "$M/one" > "$M/profiles"
  assert_ok start_session
  assert_ok psd_with "$BASE" unsync
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$M/two" two2
  assert_ok psd resync
  [[ -e "$M/two-back-ovfs/.psd-complete" ]] || fail "two not resynced"
  profile_write "$M/two" two3
  reboot_sim
  assert_ok psd startup
  assert_version "$M/two" two2
}

test_stale_session_file_unsync_of_older_session() {
  build_base release || return
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  profile_new "$M/two" two1
  echo "$M/one" > "$M/profiles"
  assert_ok start_session
  assert_ok psd_with "$BASE" unsync
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$M/two" two2
  assert_ok psd unsync
  assert_realdir "$M/two"
  assert_version "$M/two" two2
}

test_unsync_keeps_session_with_unknown_mount() {
  # a profile of an older session that left the config: unsync cannot find
  # it, so the session must not end as if all were on disk
  build_base release || return
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  profile_new "$M/two" two1
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  echo "$M/one" > "$M/profiles"
  assert_fails psd unsync
  [[ -f "$XDG_RUNTIME_DIR/psd.pid" ]] || fail "PID removed with two still in tmpfs"
  assert_symlink "$M/two"
}

test_no_stamp_with_uncopied_mount() {
  # a profile of an older session left its def mid-session; the new resync
  # cannot copy it, so its unmarked copy must keep the older recovery rule
  build_base release || return
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  profile_new "$M/two" two1
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$M/two" two2
  sleep 1.1
  assert_ok psd_with "$BASE" resync
  echo "$M/one" > "$M/profiles"
  assert_ok psd resync
  grep -qx PSD_SESSION_MARKERS=1 "$XDG_CONFIG_HOME/psd/.psd.conf" &&
    fail "stamped although two was not copied"
  reboot_sim
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd startup
  assert_version "$M/two" two2
}

test_unknown_dead_mount_does_not_block_later_stops() {
  # an older session's profile left its list; under systemd unsync fails,
  # the daemons are killed and recover runs. Later sessions this boot must
  # stop cleanly, and the profile's copies must all survive.
  build_base release || return
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  profile_new "$M/two" two1
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$M/two" two2
  sleep 1.1
  assert_ok psd_with "$BASE" resync
  echo "$M/one" > "$M/profiles"
  assert_fails psd unsync
  kill_daemons
  assert_ok psd recover
  grep -q 'does not know any more' "$T_LOG" || fail "no warning about the unknown mount"
  assert_ok start_session
  assert_ok psd unsync
  reboot_sim
  printf '%s\n' "$M/one" "$M/two" > "$M/profiles"
  assert_ok psd startup
  grep -rlqx 'two2' "$M"/two* 2>/dev/null || fail "two2 was lost"
}

test_inherited_snapshot_recovered_by_older_rule() {
  # our session crashes, an older psd recovers it and starts its own
  # session, keeping our config snapshot; that session crashes too
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  reboot_sim
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v2
  sleep 1.1
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v3
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
}

# torn_rsync: a disk that fills up: new copies fail, and a copy into BACKUP
# in place stops half way
torn_rsync() {
  mkdir -p "$T/shim2"
  ln -sf "$T_SRC/test/shim" "$T/shim2/rsync"
  cat > "$T_BIN/rsync" <<EOS
#!/bin/bash
case "\$*" in
  *back-ovfs.new*) exit 11 ;;
  *-backup/) cp -f "\${@: -2:1}/prefs.js" "\${@: -1}/prefs.js"; exit 11 ;;
esac
PATH=\${PATH#"$T_SHIMS:"}
exec "$T/shim2/rsync" "\$@"
EOS
  chmod 755 "$T_BIN/rsync"
  ln -sf "$T_BIN/rsync" "$T_SHIMS/rsync"
}

test_disk_full_stop_in_first_hour_keeps_backup_intact() {
  # no copy on disk yet but BACKUP; it must never be written in place
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  torn_rsync
  psd unsync
  kill_daemons
  psd recover
  reboot_sim
  unstub_cmd rsync
  psd startup
  assert_version "$P" v1
}

test_restart_after_failed_stop_without_recover() {
  # a unit without ExecStopPost (not reloaded after an upgrade); the next
  # start must recover instead of trusting the stale PID
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  stub_cmd rsync '*-back-ovfs.new/'
  assert_fails psd unsync
  unstub_cmd rsync
  kill_daemons
  assert_ok start_session
  assert_symlink "$P"
  assert_ok psd unsync
  assert_realdir "$P"
  assert_version "$P" v3
}
