# shellcheck shell=bash
# Fault matrix: kill psd before each of its mutating calls in turn, crash and
# reboot, and check that recovery lands on the last durable version or newer,
# and that a normal session works afterwards.

P_A() { echo "$XDG_CONFIG_HOME/psdtest-a"; }

fault_reset() {
  unmount_all
  rm -rf "$(P_A)" "$(P_A)"-* "$XDG_CONFIG_HOME/psd/.psd.conf"
  reboot_sim
}

# fault_matrix <setup> <action> <accepted versions...>
fault_matrix() {
  local setup=$1 action=$2; shift 2
  local n=1 hit v ok a P calls
  P=$(P_A)
  while :; do
    if (( n >= 200 )); then
      fail "still hitting faults at call $n, giving up"
      return
    fi
    fault_reset
    "$setup" || { fail "setup $setup failed"; return; }
    rm -f "$PSD_SHIM_COUNT"
    PSD_FAULT=$n:kill "$action"
    hit=$?
    calls=$(cat "$PSD_SHIM_COUNT" 2>/dev/null || echo 0)
    case $hit in
      0)
        (( calls < n )) || { fail "call $n ran but no kill happened"; return; }
        ;;
      137|9) ;;
      *)
        fail "$action exited $hit with a kill planned at call $n"
        return
        ;;
    esac
    reboot_sim
    psd startup || fail "kill before call $n: startup failed afterwards"
    v=$(profile_version "$P")
    ok=
    for a in "$@"; do [[ "$v" == "$a" ]] && ok=1; done
    [[ -n "$ok" ]] || fail "kill before call $n: recovered '$v', expected one of: $*"
    # the next session must work and keep what was recovered
    if [[ -n "$ok" ]]; then
      if start_session && profile_write "$P" next && psd unsync; then
        assert_version "$P" next
      else
        fail "kill before call $n: next session failed"
      fi
    fi
    (( hit == 0 )) && break
    n=$(( n + 1 ))
  done
  (( n > 1 )) || fail "fault never triggered"
}

setup_fresh() {
  profile_new "$(P_A)" v1
}

setup_running() {
  local P; P=$(P_A)
  profile_new "$P" v1
  start_session || return
  profile_write "$P" v2
  psd resync || return
  profile_write "$P" v3
}

setup_crashed() {
  setup_running || return
  reboot_sim
}

act_resync() { psd resync; }
act_unsync() { psd unsync; }
act_startup() { psd startup; }

test_kill_during_initial_sync() {
  fault_matrix setup_fresh start_session v1
}

test_kill_during_resync() {
  fault_matrix setup_running act_resync v2 v3
}

test_kill_during_unsync() {
  fault_matrix setup_running act_unsync v2 v3
}

test_kill_during_recovery() {
  fault_matrix setup_crashed act_startup v2
}

# fail_matrix <setup> <action>: make each mutating call of <action> fail in
# turn; whatever psd then reports, the next resync and unsync must save the
# newest data
fail_matrix() {
  local setup=$1 action=$2 n=1 calls P
  P=$(P_A)
  while (( n < 200 )); do
    fault_reset
    "$setup" || { fail "setup $setup failed"; return; }
    rm -f "$PSD_SHIM_COUNT"
    PSD_TRACE=$T/calls PSD_FAULT=$n:fail "$action"
    calls=$(cat "$PSD_SHIM_COUNT" 2>/dev/null || echo 0)
    psd resync
    if ! psd unsync; then
      # one failed copy may leave the session for recover
      psd recover || fail "fail at call $n: recover failed"
    fi
    [[ "$(profile_version "$P")" == v3 ]] ||
      fail "fail at call $n ($(sed -n "${n}p" "$T/calls" 2>/dev/null)): got $(profile_version "$P")"
    (( calls >= n )) || break
    n=$(( n + 1 ))
  done
  (( n > 1 )) || fail "fault never triggered"
}

test_fail_during_resync() {
  fail_matrix setup_running act_resync
}

test_fail_during_unsync() {
  fail_matrix setup_running act_unsync
}
