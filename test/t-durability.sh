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
  export PSD_TRACE=$T/trace
  assert_ok psd resync
  assert_trace_order \
    '^rm -f .*-back-ovfs/\.psd-complete$' \
    '^sync -f .*-back-ovfs$' \
    '^rsync .* .*-back-ovfs/$' \
    '^sync -f .*-back-ovfs$' \
    '^touch .*-back-ovfs/\.psd-complete$' \
    '^sync -f .*-back-ovfs$'
}

test_unsync_flushes_before_restore() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  export PSD_TRACE=$T/trace
  assert_ok psd unsync
  # the unsync's own copy, not the resync it starts with
  assert_trace_order \
    '^unlink ' \
    '^rm -f .*-back-ovfs/\.psd-complete$' \
    '^sync -f .*-back-ovfs$' \
    '^rsync .*/psd/[^ ]*/ .*-back-ovfs/$' \
    '^sync -f .*-back-ovfs$' \
    '^touch .*-back-ovfs/\.psd-complete$' \
    '^rsync .*-back-ovfs/ .*-backup/$' \
    '^sync -f .*-backup$' \
    '^mv --no-target-directory .*-backup .*/psdtest-a$'
}

test_initial_sync_clears_stale_marker_first() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  assert_ok psd resync
  assert_ok psd unsync
  [[ -e "$P-back-ovfs/.psd-complete" ]] || fail "setup: no marker left by unsync"
  export PSD_TRACE=$T/trace
  assert_ok start_session
  assert_trace_order \
    '^rm -f .*-back-ovfs/\.psd-complete$' \
    '^sync -f .*-back-ovfs$' \
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
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/fuse-overlayfs"
  chmod 755 "$T/bin/fuse-overlayfs"
  rm "$T_SHIMS/fuse-overlayfs"
  ln -s "$T/bin/fuse-overlayfs" "$T_SHIMS/fuse-overlayfs"
  psd startup
  psd resync
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
}
