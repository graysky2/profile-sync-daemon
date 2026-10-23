# shellcheck shell=bash
# Unsync when the overlay will not unmount cleanly.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }
TMP_A() { echo "$XDG_RUNTIME_DIR/psd/$(id -un)-psdtest-a"; }

test_busy_mount_detached_lazily() {
  [[ -z "${PSD_REAL_FUSE:-}" ]] || { skip "needs the fake mount"; return; }
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  realpath "$(TMP_A)" >> "$PSD_FAKE_BUSY"
  export PSD_TRACE=$T/trace
  assert_ok psd unsync
  grep -q '^fusermount3 -uz ' "$PSD_TRACE" || fail "no lazy unmount"
  assert_realdir "$P"
  assert_version "$P" v2
  assert_absent "$(TMP_A)"
}

test_unmount_failure_removes_nothing() {
  local P; P=$(P_A)
  profile_new "$P" v1
  assert_ok start_session
  profile_write "$P" v2
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/fusermount3"
  chmod 755 "$T/bin/fusermount3"
  ln -sf "$T/bin/fusermount3" "$T_SHIMS/fusermount3"
  assert_fails psd unsync
  # still mounted and intact in tmpfs
  assert_version "$(TMP_A)" v2
  # and what reached disk is recovered after a crash
  ln -sf "$T_SRC/test/shim" "$T_SHIMS/fusermount3"
  reboot_sim
  assert_ok psd startup
  assert_version "$P" v2
}

test_unmount_failure_does_not_stop_other_profiles() {
  write_conf 'BROWSERS=(psdtest-a psdtest-b)'
  local A B
  A=$(P_A)
  B=$XDG_CONFIG_HOME/psdtest-b
  profile_new "$A" a1
  profile_new "$B" b1
  assert_ok start_session
  profile_write "$A" a2
  profile_write "$B" b2
  # only psdtest-a refuses to unmount
  mkdir -p "$T/shim2"
  ln -s "$T_SRC/test/shim" "$T/shim2/fusermount3"
  cat > "$T/bin/fusermount3" <<EOS
#!/bin/bash
case "\$*" in *psdtest-a*) exit 1 ;; esac
PATH=\${PATH#"$T_SHIMS:"}
exec "$T/shim2/fusermount3" "\$@"
EOS
  chmod 755 "$T/bin/fusermount3"
  ln -sf "$T/bin/fusermount3" "$T_SHIMS/fusermount3"
  assert_fails psd unsync
  assert_realdir "$B"
  assert_version "$B" b2
  ln -sf "$T_SRC/test/shim" "$T_SHIMS/fusermount3"
  reboot_sim
  assert_ok psd startup
  assert_version "$A" a2
}
