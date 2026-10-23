#!/bin/bash
# Run the psd test suite with real fuse-overlayfs mounts. Run this on the
# host as your normal user before installing a build.
#
# Everything happens in a scratch dir under $TMPDIR: XDG dirs, SHAREDIR and
# BINDIR are redirected there and only the test browser defs (process names
# psdtst-*) are used, so your real profiles, config and running psd are not
# touched.
#
# The scratch dir defaults to ~/.cache/psd-test so profiles sit on the same
# filesystem as real ones (rename, xattr behaviour); set TMPDIR to override.
#
# Usage: test/host.sh [test-file-or-pattern...]

if [[ $EUID -eq 0 ]]; then
  echo "host.sh: run as your normal user, not root" >&2
  exit 1
fi
for bin in fuse-overlayfs fusermount3 findmnt; do
  command -v "$bin" >/dev/null || { echo "host.sh: missing $bin" >&2; exit 1; }
done
[[ -c /dev/fuse ]] || { echo "host.sh: /dev/fuse missing (modprobe fuse)" >&2; exit 1; }

if [[ -z "${TMPDIR:-}" ]]; then
  TMPDIR=${XDG_CACHE_HOME:-$HOME/.cache}/psd-test
  mkdir -p "$TMPDIR" || exit 1
  export TMPDIR
fi

PSD_REAL_FUSE=1 exec "$(dirname -- "$0")/run.sh" "$@"
