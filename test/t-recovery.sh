# shellcheck shell=bash
# Crash recovery: power loss at rest, then the next startup.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }

test_crash_after_initial_sync() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2   # only in tmpfs, never durable
  reboot_sim

  assert_ok psd startup
  assert_realdir "$P"
  assert_version "$P" v1
  assert_absent "$P-backup"
}

test_crash_after_resync() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  reboot_sim

  assert_ok psd startup
  assert_realdir "$P"
  assert_version "$P" v2
  assert_absent "$P-backup"
}

test_recovered_profile_syncs_again() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  reboot_sim

  assert_ok start_session
  assert_symlink "$P"
  assert_version "$P" v2
  profile_write "$P" v3
  assert_ok psd unsync
  assert_version "$P" v3
}

test_crash_snapshot_kept() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  reboot_sim
  assert_ok psd startup
  local n
  n=$(find "$XDG_CONFIG_HOME" -maxdepth 1 -name 'psdtest-a-backup-crashrecovery-*' | wc -l)
  (( n >= 1 )) || fail "no crashrecovery snapshot created"
}

test_snapshot_from_crash_is_replaced() {
  # the config snapshot survives a crash; the next session must not keep
  # using it, or a browser added since is synced but never unsynced
  local A=$XDG_CONFIG_HOME/psdtest-a B=$XDG_CONFIG_HOME/psdtest-b
  profile_new "$A" a1
  profile_new "$B" b1
  assert_ok start_session
  reboot_sim
  write_conf 'BROWSERS=(psdtest-a psdtest-b)'
  assert_ok start_session
  assert_symlink "$B"
  profile_write "$B" b2
  assert_ok psd unsync
  assert_realdir "$B"
  assert_version "$B" b2
}

test_crash_sets_older_copy_aside_for_rotation() {
  # BACKUP is older than a copy the session marked, so it is rotated with
  # the snapshots instead of piling up
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
  compgen -G "$P-backup-crashrecovery-*-start" >/dev/null || fail "BACKUP not set aside for rotation"
  compgen -G "$P-backup-crashrecovery-*-unused" >/dev/null && fail "BACKUP kept as an unrotated copy"
}

test_replay_failure_keeps_everything() {
  # the dead mount's writes cannot be copied (disk full); recovery stops
  # rather than restoring an older copy, and finishes once it can
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  kill_daemons
  stub_cmd fuse-overlayfs '*'
  assert_fails psd recover
  assert_symlink "$P"
  # dangling, so a browser cannot start a fresh profile there
  [[ -e "$P" ]] && fail "the link leads to a usable dir"
  unstub_cmd fuse-overlayfs
  assert_ok psd recover
  assert_version "$P" v3
}
