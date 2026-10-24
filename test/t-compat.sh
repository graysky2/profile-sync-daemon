# shellcheck shell=bash
# Mixed versions: state left by an older build must be handled by this build
# and the other way round, so the owner can upgrade or roll back at any time.
# Two bases are checked: the latest release tag (what users run) and the
# merge-base with master (what the branch started from). PSD_COMPAT_REF
# overrides the release tag.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }

base_crash_recovered_by_new() {
  build_base "$1" || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v2
  # resyncs come at least a second after the initial sync in real use; old
  # sessions are told apart by ctime at one-second resolution
  sleep 1.1
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v3
  reboot_sim

  assert_ok psd startup
  assert_version "$P" v2
  assert_ok start_session
  profile_write "$P" v4
  assert_ok psd unsync
  assert_version "$P" v4
}

new_crash_recovered_by_base() {
  build_base "$1" || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  reboot_sim

  assert_ok psd_with "$BASE" startup
  assert_version "$P" v2
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v4
  assert_ok psd_with "$BASE" unsync
  assert_version "$P" v4
}

swap_to_new_mid_session() {
  build_base "$1" || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  assert_ok psd unsync
  assert_realdir "$P"
  assert_version "$P" v3
}

swap_to_base_mid_session() {
  build_base "$1" || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v3
  assert_ok psd_with "$BASE" unsync
  assert_realdir "$P"
  assert_version "$P" v3
}

test_release_crash_recovered_by_new() {
  base_crash_recovered_by_new release
}
test_release_recovers_new_crash() { new_crash_recovered_by_base release; }
test_release_swap_to_new() { swap_to_new_mid_session release; }
test_release_swap_from_new() { swap_to_base_mid_session release; }

test_branch_crash_recovered_by_new() { base_crash_recovered_by_new branch; }
test_branch_recovers_new_crash() { new_crash_recovered_by_base branch; }
test_branch_swap_to_new() { swap_to_new_mid_session branch; }
test_branch_swap_from_new() { swap_to_base_mid_session branch; }

test_release_crash_before_first_resync() {
  # 7.04 creates an empty back-ovfs at the initial sync; never pick it
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v2
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v1
}

test_branch_stale_back_ovfs_not_promoted() {
  # a 6c76f9e session writes markers but no stamp, so it reads as legacy;
  # its unsync leaves a marked back-ovfs, the profile is then used without
  # psd, and the next 6c76f9e session crashes before its first resync
  build_base branch || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  assert_ok psd_with "$BASE" resync
  assert_ok psd_with "$BASE" unsync
  profile_write "$P" v2
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  if [[ $(stat -c %Z "$P-back-ovfs") -ne $(stat -c %Z "$P-backup") ]]; then
    skip "back-ovfs and backup changed in different seconds, rerun"
    return
  fi
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
}

test_kill_during_recovery_of_release_crash() {
  # recovery of an older session picks its copy without a marker; being
  # killed half way must not undo that choice
  build_base release || return
  local P n=1 hit
  P=$(P_A)
  while (( n < 200 )); do
    unmount_all
    rm -rf "$P" "$P"-* "$XDG_CONFIG_HOME/psd/.psd.conf" "$XDG_CONFIG_HOME/psd/.psd-session"
    reboot_sim
    profile_new "$P" v1
    if ! { psd_with "$BASE" startup && psd_with "$BASE" resync; }; then
      fail "setup failed"
      return
    fi
    profile_write "$P" v2
    sleep 1.1
    psd_with "$BASE" resync || { fail "setup failed"; return; }
    profile_write "$P" v3
    reboot_sim
    PSD_FAULT=$n:kill psd startup
    hit=$?
    reboot_sim
    psd startup || fail "kill before call $n: startup failed"
    assert_version "$P" v2
    (( hit == 137 || hit == 9 )) || break
    n=$(( n + 1 ))
  done
  (( n > 1 )) || fail "fault never triggered"
}

test_release_session_dead_mount_unsync() {
  # an older session, upgraded, whose fuse daemon died; the copy cannot be
  # replayed, so the older session's rule picks the newer copy on disk
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v2
  sleep 1.1
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v3
  kill_daemons
  # the dead mount's writes cannot be copied; the session is kept for
  # another try, and after a reboot the older rule picks the newer copy
  stub_cmd fuse-overlayfs '*'
  assert_fails psd unsync
  assert_symlink "$P"
  reboot_sim
  unstub_cmd fuse-overlayfs
  assert_ok psd startup
  assert_version "$P" v2
}

test_marker_left_by_clean_stop_not_trusted_after_downgrade() {
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  assert_ok psd unsync
  profile_write "$P" v3
  sleep 1.1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v4
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v3
}

test_marker_carried_by_release_not_trusted() {
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  reboot_sim
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  profile_write "$P" v3
  sleep 1.1
  assert_ok psd_with "$BASE" resync
  assert_ok psd_with "$BASE" unsync
  profile_write "$P" v4
  sleep 1.1
  assert_ok psd_with "$BASE" startup
  assert_ok psd_with "$BASE" resync
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v4
}
