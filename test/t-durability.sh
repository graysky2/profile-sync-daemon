# shellcheck shell=bash
# Flush ordering, checked on the call trace: a process crash cannot show a
# missing flush (the page cache survives), so the order is asserted directly.

# assert_trace_order <regex...>: the trace has lines matching each regex, in
# this order (other lines may come between)
assert_trace_order() {
  local i=1 re line
  for re in "$@"; do
    line=$(tail -n "+$i" "$PSD_TRACE" | grep -nE -m1 -- "$re") ||
      { fail "trace: no '$re' after line $i"; return; }
    i=$(( i + ${line%%:*} ))
  done
}

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }

test_resync_flushes_around_marker() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  profile_write "$P" v2
  export PSD_TRACE=$T/trace
  assert_ok psd resync
  # the new copy is complete on disk before it replaces the current one,
  # which stays marked throughout
  assert_trace_order \
    '^rsync .* .*-back-ovfs\.new/$' \
    '^sync -f .*-back-ovfs\.new$' \
    '^touch .*-back-ovfs\.new/\.psd-complete$' \
    '^sync -f .*-back-ovfs\.new$' \
    '^mv --exchange --no-target-directory .*-back-ovfs\.new .*-back-ovfs$' \
    '^sync -f .*-back-ovfs$'
  grep -v -- --dry-run "$PSD_TRACE" | grep -E '^(rm|rsync|touch) .*-back-ovfs/' &&
    fail "the current copy was changed in place"
  assert_absent "$P-back-ovfs.new"
}

test_unsync_flushes_before_restore() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  profile_write "$P" v2
  export PSD_TRACE=$T/trace
  assert_ok psd unsync
  # the resync unsync starts with makes the copy (its own copy finds
  # nothing changed since); the link goes only once the data is on disk
  assert_trace_order \
    '^rsync .*/psdtest-a/ .*-back-ovfs\.new/$' \
    '^sync -f .*-back-ovfs\.new$' \
    '^touch .*-back-ovfs\.new/\.psd-complete$' \
    '^sync -f .*-back-ovfs\.new$' \
    '^mv --exchange --no-target-directory .*-back-ovfs\.new .*-back-ovfs$' \
    '^sync -f .*-back-ovfs$' \
    '^rsync .*-back-ovfs/ .*-backup/$' \
    '^sync -f .*-backup$' \
    '^unlink ' \
    '^mv --no-target-directory .*-backup .*/psdtest-a$'
}

test_initial_sync_moves_stale_copy_first() {
  # a copy left by an older psd's clean stop must be out of the way, and
  # untouched, before the profile becomes BACKUP
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  assert_ok psd unsync
  assert_absent "$P-back-ovfs"
  mv "$P-back-ovfs.base" "$P-back-ovfs"
  export PSD_TRACE=$T/trace
  assert_ok start_session
  assert_trace_order \
    '^mv --no-target-directory .*-back-ovfs .*-back-ovfs\.base$' \
    '^sync -f .*-back-ovfs\.base$' \
    '^mv --no-target-directory .*/psdtest-a .*-backup$'
  assert_ok psd unsync
}

test_mount_failure_leaves_no_stale_marker() {
  # bug 12: profile used without psd after a clean session, then the mount
  # fails; recovery must not prefer the old back-ovfs
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  assert_ok psd unsync
  profile_write "$P" v2          # used without psd
  printf '#!/bin/sh\nexit 1\n' > "$T_BIN/fuse-overlayfs"
  chmod 755 "$T_BIN/fuse-overlayfs"
  rm "$T_SHIMS/fuse-overlayfs"
  ln -s "$T_BIN/fuse-overlayfs" "$T_SHIMS/fuse-overlayfs"
  psd startup
  psd resync
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
}

test_resync_without_exchange_falls_back() {
  # a filesystem without RENAME_EXCHANGE: copy in place as before
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  # what mv says when the filesystem cannot swap
  # shellcheck disable=SC2016 # the stub's own variables
  printf '#!/bin/bash\ncase "$*" in *--exchange*) echo "mv: cannot exchange: Invalid argument" >&2; exit 1 ;; esac\nPATH=${PATH#"%s:"}\nexec "%s/shim2/mv" "$@"\n' "$T_SHIMS" "$T" > "$T_BIN/mv"
  mkdir -p "$T/shim2" && ln -sf "$T_SRC/test/shim" "$T/shim2/mv"
  chmod 755 "$T_BIN/mv" && ln -sf "$T_BIN/mv" "$T_SHIMS/mv"
  profile_write "$P" v3
  assert_ok psd resync
  assert_version "$P-back-ovfs" v3
  assert_absent "$P-back-ovfs.new"
  profile_write "$P" v4
  assert_ok psd unsync
  assert_version "$P" v4
}

test_leftover_new_copy_never_used() {
  # a swap killed after the exchange leaves the previous copy as .new, marked
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  cp -a "$P-back-ovfs" "$P-back-ovfs.new"
  profile_write "$P-back-ovfs.new" v9
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
  assert_ok start_session
  assert_absent "$P-back-ovfs.new"
  assert_ok psd unsync
  assert_version "$P" v2
}

test_failed_swap_keeps_current_copy() {
  # any other failure of the swap: report it, never copy in place
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  stub_cmd mv '*--exchange*'
  profile_write "$P" v3
  assert_fails psd resync
  assert_version "$P-back-ovfs" v2
  [[ -e "$P-back-ovfs/.psd-complete" ]] || fail "current copy lost its marker"
  assert_absent "$P-back-ovfs.new"
  unstub_cmd mv
  assert_ok psd unsync
  assert_version "$P" v3
}

test_old_coreutils_copies_in_place() {
  # mv without --exchange (coreutils before 9.5): no new copy is built
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  # shellcheck disable=SC2016 # the stub's own variables
  printf '#!/bin/bash\nif [[ "$1" == --help ]]; then echo "Usage: mv"; exit 0; fi\nPATH=${PATH#"%s:"}\nexec "%s/shim2/mv" "$@"\n' "$T_SHIMS" "$T" > "$T_BIN/mv"
  mkdir -p "$T/shim2" && ln -sf "$T_SRC/test/shim" "$T/shim2/mv"
  chmod 755 "$T_BIN/mv" && ln -sf "$T_BIN/mv" "$T_SHIMS/mv"
  export PSD_TRACE=$T/trace
  profile_write "$P" v2
  assert_ok psd resync
  grep -q -- '-back-ovfs\.new' "$PSD_TRACE" && fail "built a new copy it cannot swap in"
  assert_version "$P-back-ovfs" v2
  profile_write "$P" v3
  assert_ok psd unsync
  assert_version "$P" v3
}

test_read_only_dir_in_profile() {
  # old copies must be removable although a dir in them is read-only
  local P; P=$(P_A)
  profile_new "$P" v1
  mkdir "$P/ext"
  echo old > "$P/ext/manifest"
  chmod 555 "$P/ext"
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd resync
  profile_write "$P" v3
  assert_ok psd resync
  chmod u+w "$P/ext"
  rm -rf "$P/ext"
  profile_write "$P" v4
  assert_ok psd resync
  assert_absent "$P-back-ovfs/ext"
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v4
  assert_absent "$P/ext"
}

test_downgrade_recovers_crash_before_first_resync() {
  # psd 7.04 recovers by ctime in whole seconds; last session's copy must
  # not look newer than the profile this session moved to BACKUP
  build_base release || return
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  assert_ok psd unsync
  profile_write "$P" v3
  assert_ok start_session
  reboot_sim
  assert_ok psd_with "$BASE" startup
  assert_version "$P" v3
}

test_first_copy_links_last_session() {
  # the first copy of a session builds on the last session's
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  assert_ok psd unsync
  assert_ok start_session
  [[ -d "$P-back-ovfs.base" ]] || fail "last session's copy not kept as base"
  export PSD_TRACE=$T/trace
  assert_ok psd resync
  grep -qE '^rsync .*--link-dest=.*-back-ovfs\.base ' "$PSD_TRACE" || fail "first copy not linked"
  assert_absent "$P-back-ovfs.base"
  assert_ok psd unsync
  assert_version "$P" v1
}

test_unchanged_profile_not_copied() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  export PSD_TRACE=$T/trace
  assert_ok psd resync
  grep -q -- '-back-ovfs\.new' "$PSD_TRACE" && fail "copied an unchanged profile"
  profile_write "$P" v2
  assert_ok psd resync
  assert_version "$P-back-ovfs" v2
  assert_ok psd unsync
  assert_version "$P" v2
}

test_vanished_files_are_not_a_failure() {
  # rsync exits 24 when files vanish during the copy, e.g. journals
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  mkdir -p "$T/shim2"
  ln -sf "$T_SRC/test/shim" "$T/shim2/rsync"
  cat > "$T_BIN/rsync" <<EOS
#!/bin/bash
PATH=\${PATH#"$T_SHIMS:"}
"$T/shim2/rsync" "\$@" || exit
case "\$*" in *--dry-run*) exit 0 ;; esac
exit 24
EOS
  chmod 755 "$T_BIN/rsync"
  ln -sf "$T_BIN/rsync" "$T_SHIMS/rsync"
  profile_write "$P" v2
  assert_ok psd resync
  assert_version "$P-back-ovfs" v2
  unstub_cmd rsync
  assert_ok psd unsync
  assert_version "$P" v2
}
