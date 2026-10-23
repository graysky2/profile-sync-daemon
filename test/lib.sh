# shellcheck shell=bash
# Shared setup and assertions for the psd test suite. Sourced by test/run.sh.
#
# Every test runs in its own scratch tree: HOME, XDG_CONFIG_HOME,
# XDG_RUNTIME_DIR, SHAREDIR and BINDIR all point inside it, psd runs with a
# scrubbed environment, and only the test browser defs in test/browsers are
# installed, so real browsers, profiles and the running psd are never touched.

T_SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# build_psd <script.in> <dest>: scratch copy with every install path and HOME
# redirected into $T. Refuses to produce a build that could reach real paths.
build_psd() {
  sed -e 's/@VERSION@/test/' \
    -e "s|@SHAREDIR@|$T_SHARE|" \
    -e "s|@BINDIR@|$T_BIN|" \
    -e "s|^SHAREDIR=\"/usr/share/psd\"$|SHAREDIR=\"$T_SHARE\"|" \
    -e "s|/usr/bin/psd-suspend-sync|$T_BIN/psd-suspend-sync|g" \
    -e "s|^HOME=\"\$(getent passwd \"\$user\" \| cut -d: -f6)\"$|HOME=\"$T/home\"|" \
    "$1" > "$2"
  chmod 755 "$2"
  if ! grep -qxF "SHAREDIR=\"$T_SHARE\"" "$2" ||
    ! grep -qxF "HOME=\"$T/home\"" "$2" ||
    grep -qE '@[A-Z]+@|/usr/share/psd|/usr/bin/psd-suspend-sync|getent passwd' "$2"; then
    echo "build_psd: $1 still references real paths, refusing to run it" >&2
    exit 3
  fi
}

# build_base release|branch: sets BASE to a scratch build of that ref: the
# latest release tag (PSD_COMPAT_REF overrides it) or the merge-base with
# master
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
  # shellcheck disable=SC2034 # used by the test files
  BASE=$T_BIN/psd-base
}

# setup_env: fresh scratch tree, config, and shim dir for one test
setup_env() {
  T=$(mktemp -d "$T_BASE/t.XXXXXX")
  T_SHARE=$T/share
  # executables live apart from the data, which may be on a noexec tmpfs
  T_BIN=$T_XBASE/${T##*/}
  T_SHIMS=$T/shims
  T_LOG=$T/log
  mkdir -p "$T_SHARE/browsers" "$T_BIN" "$T_SHIMS" "$T/home" "$T/config/psd" \
    "$T/run" "$T/tmp" "$T/fakemnt"
  chmod 700 "$T/run"
  cp "$T_SRC"/test/browsers/* "$T_SHARE/browsers/"
  build_psd "$T_SRC/common/profile-sync-daemon.in" "$T_BIN/profile-sync-daemon"
  printf '#!/bin/sh\nexit 0\n' > "$T_BIN/psd-suspend-sync"
  chmod 755 "$T_BIN/psd-suspend-sync"

  export XDG_CONFIG_HOME=$T/config
  export XDG_RUNTIME_DIR=$T/run
  export TMPDIR=$T/tmp
  export PSD_FAKE_MNT=$T/fakemnt/table
  export PSD_FAKE_BUSY=$T/fakemnt/busy
  export PSD_SHIM_COUNT=$T/fakemnt/count
  export PSD_SHIM_VIOLATIONS=$T/violations
  unset PSD_TRACE PSD_FAULT
  : > "$PSD_FAKE_MNT"
  : > "$PSD_FAKE_MNT.dead"
  : > "$PSD_FAKE_MNT.upper"
  : > "$PSD_FAKE_BUSY"

  local name
  for name in rsync mv rm rmdir mkdir cp touch ln unlink install chmod chown \
    sync fuse-overlayfs fusermount3 mountpoint findmnt pkill; do
    ln -s "$T_SRC/test/shim" "$T_SHIMS/$name"
  done

  write_conf 'BROWSERS=(psdtest-a)'
}

teardown_env() {
  [[ -n "${T:-}" && -d "$T" ]] || return 0
  unmount_all
  # tests may leave read-only dirs behind
  chmod -R u+w "$T" 2>/dev/null
  rm -rf "$T" "$T_BIN"
}

# write_conf <lines...>: replace psd.conf, always with suspend sync off
write_conf() {
  printf '%s\n' 'USE_SUSPSYNC="no"' "$@" > "$XDG_CONFIG_HOME/psd/psd.conf"
}

# unmount_all: drop every mount under the scratch tree (real or fake)
unmount_all() {
  : > "$PSD_FAKE_MNT"
  : > "$PSD_FAKE_MNT.dead"
  : > "$PSD_FAKE_MNT.upper"
  : > "$PSD_FAKE_BUSY"
  kill_fake_daemons
  [[ -n "${PSD_REAL_FUSE:-}" ]] || return 0
  local m
  while read -r m; do
    fusermount3 -u "$m" 2>/dev/null || fusermount3 -uz "$m" 2>/dev/null
  done < <(findmnt -rn -o TARGET | grep -F "$T/" | sort -r)
}

kill_fake_daemons() {
  local pid
  [[ -f "$PSD_FAKE_MNT.pids" ]] || return 0
  while read -r pid _; do
    kill "$pid" 2>/dev/null
  done < "$PSD_FAKE_MNT.pids"
  : > "$PSD_FAKE_MNT.pids"
}

# kill_daemons: what systemd does to psd.service's fuse daemons after a
# failed start or stop; the mounts stay behind, dead
kill_daemons() {
  if [[ -n "${PSD_REAL_FUSE:-}" ]]; then
    pkill -KILL -u "$(id -u)" -f "^fuse-overlayfs .*$T/" 2>/dev/null
    sleep 0.2
  else
    # a dead fake mount: what was written is in its upper dir, the mount
    # stays in the mount table until it is detached, which leaves the empty
    # mountpoint dir
    local m u
    while read -r m; do
      [[ -n "$m" ]] || continue
      u=$(awk -v m="$m" '$1 == m { u = $2 } END { print u }' "$PSD_FAKE_MNT.upper")
      if [[ -n "$u" && -d "$u" ]]; then
        find "$u" -mindepth 1 -delete
        cp -a "$m/." "$u/"
        touch "$u/.fake-opaque"
      fi
      find "$m" -mindepth 1 -delete
      echo "$m" >> "$PSD_FAKE_MNT.dead"
    done < "$PSD_FAKE_MNT"
    : > "$PSD_FAKE_MNT"
    kill_fake_daemons
  fi
}

# psd_with <bin> <verb>: run a build in its own process group with a scrubbed
# environment and the shims first in PATH; output goes to $T_LOG, the exit
# status is returned (137 when the shim killed it, 124 when it hung). A real
# run takes well under a second; PSD_TEST_TIMEOUT caps a hung one.
psd_with() {
  local bin=$1; shift
  echo "### ${bin##*/} $*" >> "$T_LOG"
  local -a envv=(
    PATH="$T_SHIMS:$PATH" HOME="$T/home" LANG=C
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
    TMPDIR="$TMPDIR" LAUNCHED_BY_SYSTEMD=1
    PSD_FAKE_MNT="$PSD_FAKE_MNT" PSD_FAKE_BUSY="$PSD_FAKE_BUSY"
    PSD_SHIM_COUNT="$PSD_SHIM_COUNT" PSD_SHIM_VIOLATIONS="$PSD_SHIM_VIOLATIONS"
    PSD_TRACE="${PSD_TRACE:-}" PSD_FAULT="${PSD_FAULT:-}"
    PSD_REAL_FUSE="${PSD_REAL_FUSE:-}"
  )
  # the subshell keeps bash's "Killed" job notice for injected kills quiet
  (timeout -k 5 "${PSD_TEST_TIMEOUT:-60}" setsid -w env -i "${envv[@]}" "$bin" "$@" >> "$T_LOG" 2>&1; exit $?) 2>/dev/null
}

psd() {
  psd_with "$T_BIN/profile-sync-daemon" "$@"
}

# start_session: what psd.service does at login
start_session() {
  psd startup && psd resync
}

# reboot_sim: crash and reboot; tmpfs and all mounts are gone, the disk is
# kept. This is a process crash, not a power cut: the page cache survives, so
# flush ordering is checked separately through PSD_TRACE.
reboot_sim() {
  unmount_all
  rm -rf "$XDG_RUNTIME_DIR"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  rm -f "$PSD_SHIM_COUNT"
}

# stub_cmd <name> <pattern>: make <name> fail when its arguments match the
# glob <pattern>, otherwise run it through the normal shim
stub_cmd() {
  mkdir -p "$T/shim2"
  ln -sf "$T_SRC/test/shim" "$T/shim2/$1"
  cat > "$T_BIN/$1" <<EOS
#!/bin/bash
case "\$*" in $2) exit 1 ;; esac
PATH=\${PATH#"$T_SHIMS:"}
exec "$T/shim2/$1" "\$@"
EOS
  chmod 755 "$T_BIN/$1"
  ln -sf "$T_BIN/$1" "$T_SHIMS/$1"
}

unstub_cmd() {
  ln -sf "$T_SRC/test/shim" "$T_SHIMS/$1"
}

# ---- simulated browser profile ----------------------------------------------

# profile_new <dir> <version>: create a real on-disk profile
profile_new() {
  mkdir -p "$1/storage/default"
  profile_write "$@"
}

# profile_write <dir> <version>: what a browser does. Files must agree on the
# version (a torn copy shows up as a mismatch), and each version replaces the
# previous one's added-* file, so lost deletes and lost creates show up too.
# Sizes grow with every write so rsync's size check always sees the change;
# same-size rewrites are tested on their own with profile_rewrite.
profile_write() {
  local n
  n=$(( $(cat "$T/writes" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$T/writes"
  printf '%s %*s\n' "$2" "$n" '' > "$1/prefs.js"
  {
    printf '%s\n' "$2"
    head -c $(( 65536 + n )) /dev/zero | tr '\0' x
    printf '\n%s\n' "$2"
  } > "$1/places.sqlite"
  printf '%s %*s\n' "$2" "$n" '' > "$1/storage/default/idb"
  rm -f "$1"/added-*
  echo "$2" > "$1/added-$2"
}

# profile_rewrite <dir> <version>: overwrite prefs.js keeping its exact size,
# as a browser rewriting a page or a same-length value does
profile_rewrite() {
  local size
  size=$(stat -c %s "$1/prefs.js")
  printf '%-*s\n' "$(( size - 1 ))" "$2" > "$1/prefs.js"
}

# profile_version <dir>: the version, or "torn" or "missing"
profile_version() {
  local v added
  [[ -f "$1/prefs.js" ]] || { echo missing; return; }
  read -r v _ < "$1/prefs.js"
  added=$(cd "$1" && echo added-*)
  if [[ "$(head -n1 "$1/places.sqlite" 2>/dev/null)" != "$v" ||
    "$(tail -n1 "$1/places.sqlite" 2>/dev/null)" != "$v" ||
    "$(awk '{ print $1; exit }' "$1/storage/default/idb" 2>/dev/null)" != "$v" ||
    "$added" != "added-$v" ]]; then
    echo torn
    return
  fi
  echo "$v"
}

# ---- assertions -------------------------------------------------------------

fail() {
  echo "    $*" >> "$T/failures"
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "${3:-assert_eq}: expected '$2', got '$1'"
}

assert_version() {
  assert_eq "$(profile_version "$1")" "$2" "version of $1"
}

assert_symlink() {
  [[ -h "$1" ]] || fail "expected symlink: $1"
}

assert_realdir() {
  [[ -d "$1" && ! -h "$1" ]] || fail "expected real dir: $1"
}

assert_absent() {
  [[ ! -e "$1" && ! -h "$1" ]] || fail "expected absent: $1"
}

assert_ok() {
  "$@" || fail "command failed ($?): $*"
}

assert_fails() {
  local rc=0
  "$@" || rc=$?
  case $rc in
    0) fail "command unexpectedly succeeded: $*" ;;
    124 | 137) fail "command hung or was killed ($rc): $*" ;;
  esac
}

# tree_state <dir>: listing of every path and its content hash, for "nothing
# changed" checks
tree_state() {
  (cd "$1" && find . -path ./run -prune -o -printf '%y %p %l\n' | sort &&
    find . -path ./run -prune -o -type f -print0 | sort -z | xargs -0r sha256sum)
}

# assert_tree_unchanged <before> <dir>: compare against an earlier tree_state
assert_tree_unchanged() {
  local d
  d=$(diff <(printf '%s\n' "$1") <(tree_state "$2")) || fail "tree changed under $2:
      ${d//$'\n'/$'\n'      }"
}

# xfail <reason> <pattern>: known to fail until <reason> is fixed. Every
# failure line must match the grep -E <pattern>, so a test that also breaks
# for some other reason is not hidden.
xfail() {
  printf '%s\n%s\n' "$1" "$2" > "$T/xfail"
}
