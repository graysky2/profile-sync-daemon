# shellcheck shell=bash
# Data-safety bugs from the refactor strategy. Each is xfail until fixed;
# the fix commit removes the xfail line.

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
  xfail "bug 1: dup_check only exits for palemoon" "unexpectedly succeeded: start_session"
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

test_enforce_keeps_unused_copies() {
  xfail "bug 4: enforce deletes -unused copies" "set-aside copy was deleted"
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
