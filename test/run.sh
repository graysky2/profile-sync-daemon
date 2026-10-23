#!/bin/bash
# psd test runner.
#
# Usage: test/run.sh [test-file-or-pattern...]
#   PSD_REAL_FUSE=1  use real fuse-overlayfs mounts (see test/host.sh)
#   KEEP=1           keep scratch trees of failing tests
#   VERBOSE=1        show why expected failures failed
#
# Each test file defines test_* functions. Every function runs in a subshell
# with a fresh scratch tree. A test that calls xfail is expected to fail with
# a matching message; if it passes it is reported as XPASS so the xfail can
# be removed. A test that calls skip is counted as skipped.

set -u

# Become a child subreaper so processes orphaned by the fault injection's
# kills are reparented to this shell and reaped, instead of piling up as
# zombies under a PID 1 that does not reap (e.g. in containers).
if [[ -z "${PSD_TEST_REAPER:-}" ]] && command -v python3 >/dev/null; then
  export PSD_TEST_REAPER=1
  exec python3 -I -c 'import ctypes, os, sys
ctypes.CDLL(None).prctl(36, 1, 0, 0, 0)  # PR_SET_CHILD_SUBREAPER
os.execv("/bin/bash", ["bash"] + sys.argv[1:])' "$0" "$@"
fi

cd -- "$(dirname -- "$0")" || exit 1
# shellcheck source=test/lib.sh
. ./lib.sh

T_BASE=$(mktemp -d "${TMPDIR:-/tmp}/psd-test.XXXXXX")
# also stop anything a test left running, e.g. stand-in fuse daemons
trap 'pkill -P $$ 2>/dev/null; rm -rf "$T_BASE"' EXIT

files=()
if (( $# )); then
  shopt -s nullglob
  for a in "$@"; do
    if [[ -f "$a" ]]; then files+=("$a"); else files+=(t-*"$a"*.sh); fi
  done
  shopt -u nullglob
else
  files=(t-*.sh)
fi
(( ${#files[@]} )) || { echo "no test files match: $*" >&2; exit 1; }

# skip <reason>: the test cannot run here
skip() {
  echo "$*" > "$T/skip"
}

pass=0 bad=0 xf=0 skipped=0
for f in "${files[@]}"; do
  # a file that does not parse would silently lose its tests
  if ! err=$(bash -n "$f" 2>&1); then
    printf 'FAIL  %s: does not parse\n    %s\n' "${f%.sh}" "$err"
    bad=$((bad + 1))
    continue
  fi
  for t in $(bash -c ". ./lib.sh; . '$f'; declare -F" | awk '$3 ~ /^test_/ { print $3 }'); do
    (
      # shellcheck disable=SC1090
      . "./$f"
      setup_env
      "$t"
      rc=0
      [[ -s "$PSD_SHIM_VIOLATIONS" ]] &&
        fail "psd tried to touch a non-test process: $(< "$PSD_SHIM_VIOLATIONS")"
      [[ -s "$T/failures" ]] && rc=1
      if [[ -f "$T/skip" ]]; then
        printf 'skip  %s: %s (%s)\n' "${f%.sh}" "$t" "$(< "$T/skip")"
        rc=3
      elif [[ -f "$T/xfail" ]]; then
        { read -r reason; read -r pattern; } < "$T/xfail"
        if (( rc )) && ! grep -qvE -- "$pattern" "$T/failures"; then
          printf 'xfail %s: %s (%s)\n' "${f%.sh}" "$t" "$reason"
          [[ -n "${VERBOSE:-}" ]] && cat "$T/failures"
          rc=2
        elif (( rc )); then
          printf 'FAIL  %s: %s (expected failure for "%s" did not match /%s/)\n' \
            "${f%.sh}" "$t" "$reason" "$pattern"
          cat "$T/failures"
          rc=1
        else
          printf 'XPASS %s: %s (was: %s)\n' "${f%.sh}" "$t" "$reason"
          rc=1
        fi
      elif (( rc )); then
        printf 'FAIL  %s: %s\n' "${f%.sh}" "$t"
        cat "$T/failures"
        printf '    log: last lines\n'
        tail -n 15 "$T_LOG" 2>/dev/null | sed 's/^/      /'
      else
        printf 'ok    %s: %s\n' "${f%.sh}" "$t"
      fi
      if (( rc == 1 )) && [[ -n "${KEEP:-}" ]]; then
        unmount_all
        echo "    kept: $T"
        exit 1
      fi
      teardown_env
      exit "$rc"
    )
    case $? in
      0) pass=$((pass + 1)) ;;
      1) bad=$((bad + 1)) ;;
      2) xf=$((xf + 1)) ;;
      3) skipped=$((skipped + 1)) ;;
      *) printf 'DIED  %s: %s\n' "${f%.sh}" "$t"; bad=$((bad + 1)) ;;
    esac
  done
done

[[ -n "${KEEP:-}" ]] && (( bad )) && trap - EXIT
echo
echo "passed $pass, failed $bad, expected failures $xf, skipped $skipped"
(( pass + xf > 0 )) || { echo "nothing ran" >&2; exit 1; }
(( bad == 0 ))
