# shellcheck shell=bash
# Mixed versions: state left by an older build must be handled by this build
# and the other way round, so the owner can upgrade or roll back at any time.
# Two bases are checked: the latest release tag (what users run) and the
# merge-base with master (what the branch started from). PSD_COMPAT_REF
# overrides the release tag.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }

# build_base release|branch: sets BASE to a scratch build of that ref
build_base() {
  local ref
  if ! command -v git >/dev/null || ! git -C "$T_SRC" rev-parse --git-dir >/dev/null 2>&1; then
    skip "no git checkout"
    return 1
  fi
  case $1 in
    release) ref=${PSD_COMPAT_REF:-$(git -C "$T_SRC" describe --tags --abbrev=0 master 2>/dev/null)} ;;
    branch) ref=$(git -C "$T_SRC" merge-base HEAD master 2>/dev/null) ;;
  esac
  [[ -n "$ref" ]] || { skip "no $1 ref found"; return 1; }
  git -C "$T_SRC" show "$ref:common/profile-sync-daemon.in" > "$T/base.in" || return 1
  build_psd "$T/base.in" "$T_BIN/psd-base"
  BASE=$T_BIN/psd-base
}

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
