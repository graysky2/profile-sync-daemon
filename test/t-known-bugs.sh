# shellcheck shell=bash
# Data-safety bugs from the refactor strategy, numbered as there. Open ones
# are xfail; the fix commit removes the xfail line and the test stays.

test_preview_is_read_only() {
  xfail "bug 15: preview runs crash recovery" "tree changed"
  local P=$XDG_CONFIG_HOME/psdtest-a
  profile_new "$P" v1
  assert_ok start_session
  reboot_sim

  local before
  before=$(tree_state "$XDG_CONFIG_HOME")
  psd preview
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
}

test_duplicate_profile_names_refused() {
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one/default" one1
  profile_new "$M/two/default" two1
  printf '%s\n' "$M/one/default" "$M/two/default" > "$M/profiles"

  local before
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_fails start_session
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
}

test_profile_named_like_an_upper_dir_refused() {
  # profile "x-rw" would use profile "x"'s upper dir as its tmpfs dir
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/x" x1
  profile_new "$M/x-rw" y1
  printf '%s\n' "$M/x" "$M/x-rw" > "$M/profiles"

  local before
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_fails start_session
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
}

test_enforce_keeps_unused_copies() {
  write_conf 'BROWSERS=(psdtest-a)' 'BACKUP_LIMIT=0'
  local P=$XDG_CONFIG_HOME/psdtest-a
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  # a crash mid-resync leaves back-ovfs incomplete; recovery keeps it aside
  rm -f "$P-back-ovfs/.psd-complete"
  reboot_sim

  assert_ok start_session
  local n
  n=$(find "$XDG_CONFIG_HOME" -maxdepth 1 -name 'psdtest-a-*unused*' | wc -l)
  (( n >= 1 )) || fail "the set-aside copy was deleted"
}

test_same_size_rewrite_in_same_second_synced() {
  xfail "bug 19: rsync quick check compares whole seconds only" "prefs.js after unsync"
  local P=$XDG_CONFIG_HOME/psdtest-a
  profile_new "$P" v1
  assert_ok start_session
  # the browser wrote prefs.js, psd copied it, and the browser rewrote it
  # with the same size within the same second
  local sec
  sec=$(date +%s)
  touch -d "@$sec.100000000" "$P/prefs.js"
  assert_ok psd resync
  profile_rewrite "$P" v2
  touch -d "@$sec.200000000" "$P/prefs.js"
  assert_ok psd unsync
  local v
  read -r v _ < "$P/prefs.js"
  assert_eq "$v" v2 "prefs.js after unsync"
}
test_shipped_defs_with_default_config() {
  # the shipped browser defs with the default empty BROWSERS must work,
  # including opera's two alternative profile locations
  cp "$T_SRC"/common/browsers/* "$T_SHARE/browsers/"
  write_conf
  mkdir -p "$XDG_CONFIG_HOME/opera"
  assert_ok psd startup
  assert_ok psd preview
}

test_opera_prefers_new_location() {
  # a stale ~/.opera from before version 26 must not stop psd
  cp "$T_SRC"/common/browsers/opera "$T_SHARE/browsers/"
  write_conf 'BROWSERS=(opera)'
  mkdir -p "$T/home/.opera"
  profile_new "$XDG_CONFIG_HOME/opera" o1
  assert_ok start_session
  assert_symlink "$XDG_CONFIG_HOME/opera"
  assert_realdir "$T/home/.opera"
  profile_write "$XDG_CONFIG_HOME/opera" o2
  assert_ok psd unsync
  assert_version "$XDG_CONFIG_HOME/opera" o2
}

test_profile_of_two_browsers_refused() {
  # psdtest-m lists psdtest-a's profile as well
  write_conf 'BROWSERS=(psdtest-a psdtest-m)'
  local P=$XDG_CONFIG_HOME/psdtest-a
  profile_new "$P" v1
  mkdir -p "$XDG_CONFIG_HOME/psdtest-m"
  echo "$P" > "$XDG_CONFIG_HOME/psdtest-m/profiles"
  local before
  before=$(tree_state "$XDG_CONFIG_HOME")
  assert_fails start_session
  assert_tree_unchanged "$before" "$XDG_CONFIG_HOME"
}

test_same_profile_listed_twice_is_fine() {
  write_conf 'BROWSERS=(psdtest-m)'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/one" one1
  printf '%s\n' "$M/one" "$M/one" > "$M/profiles"
  assert_ok start_session
  profile_write "$M/one" one2
  assert_ok psd unsync
  assert_version "$M/one" one2
}

test_enforce_glob_stays_in_its_profile() {
  # bug 17: a profile named "p?" must not rotate profile "pa"'s snapshots
  write_conf 'BROWSERS=(psdtest-m)' 'BACKUP_LIMIT=0'
  local M=$XDG_CONFIG_HOME/psdtest-m
  profile_new "$M/p?" q1
  printf '%s\n' "$M/p?" > "$M/profiles"
  mkdir -p "$M/pa-backup-crashrecovery-20260101_000000" \
    "$M/pa-backup-crashrecovery-20260102_000000"

  assert_ok start_session
  [[ -d "$M/pa-backup-crashrecovery-20260101_000000" &&
    -d "$M/pa-backup-crashrecovery-20260102_000000" ]] ||
    fail "another profile's snapshots were deleted"
  assert_ok psd unsync
}

test_enforce_rotates_snapshots() {
  write_conf 'BROWSERS=(psdtest-a)' 'BACKUP_LIMIT=1'
  local P=$XDG_CONFIG_HOME/psdtest-a
  profile_new "$P" v1
  mkdir -p "$P-backup-crashrecovery-20260101_000000" \
    "$P-backup-crashrecovery-20260102_000000"
  assert_ok start_session
  assert_absent "$P-backup-crashrecovery-20260101_000000"
  assert_realdir "$P-backup-crashrecovery-20260102_000000"
  assert_ok psd unsync
}
