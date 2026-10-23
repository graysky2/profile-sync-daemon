# shellcheck shell=bash
# Normal session: startup, initial sync, resyncs, unsync.

test_full_session() {
  local P=$XDG_CONFIG_HOME/psdtest-a
  local TMP
  TMP=$XDG_RUNTIME_DIR/psd/$(id -un)-psdtest-a
  profile_new "$P" v1

  assert_ok start_session
  assert_symlink "$P"
  assert_eq "$(readlink "$P")" "$TMP" "symlink target"
  assert_realdir "$P-backup"
  assert_version "$P-backup" v1
  assert_version "$P" v1
  [[ -e "$P/.flagged" ]] || fail "missing .flagged"

  profile_write "$P" v2
  assert_ok psd resync
  assert_version "$P-back-ovfs" v2
  [[ -e "$P-back-ovfs/.psd-complete" ]] || fail "missing .psd-complete after resync"
  assert_version "$P-backup" v1

  profile_write "$P" v3
  assert_ok psd unsync
  assert_realdir "$P"
  assert_version "$P" v3
  assert_absent "$P-backup"
  assert_absent "$XDG_RUNTIME_DIR/psd.pid"
  assert_absent "$TMP"
  [[ -e "$P/.flagged" ]] && fail ".flagged left in profile"
  [[ -e "$P/.psd-complete" ]] && fail ".psd-complete left in profile"
}

test_two_browsers() {
  write_conf 'BROWSERS=(psdtest-a psdtest-b)'
  local A=$XDG_CONFIG_HOME/psdtest-a B=$XDG_CONFIG_HOME/psdtest-b
  profile_new "$A" a1
  profile_new "$B" b1

  assert_ok start_session
  assert_symlink "$A"
  assert_symlink "$B"
  profile_write "$A" a2
  profile_write "$B" b2
  assert_ok psd unsync
  assert_version "$A" a2
  assert_version "$B" b2
}

test_second_session() {
  local P=$XDG_CONFIG_HOME/psdtest-a
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  assert_ok psd unsync

  # a second session reuses the old back-ovfs as rsync basis
  assert_ok start_session
  profile_write "$P" v3
  assert_ok psd resync
  assert_version "$P-back-ovfs" v3
  assert_ok psd unsync
  assert_version "$P" v3
}

test_missing_profile_is_ignored() {
  # browser not installed: nothing to do, nothing created
  assert_ok start_session
  assert_absent "$XDG_CONFIG_HOME/psdtest-a"
  assert_ok psd unsync
  assert_absent "$XDG_CONFIG_HOME/psdtest-a"
}
