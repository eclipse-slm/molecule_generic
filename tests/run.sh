#!/usr/bin/env bash
# Checks how molecule_generic resolves and validates the driver.
set -u

cd "$(dirname "$0")"
failures=0

# expect <ok|fail> <pattern> <env assignment> [ansible-playbook args...]
expect() {
  local want=$1 pattern=$2 envassign=$3
  shift 3
  local out rc
  out=$(env -u MOLECULE_DRIVER ${envassign:+"$envassign"} \
    ansible-playbook -i localhost, driver_selection.yml "$@" 2>&1)
  rc=$?
  if [[ $want == ok && $rc -ne 0 ]] || [[ $want == fail && $rc -eq 0 ]]; then
    echo "FAIL [${envassign:-<unset>} $*]: expected $want, rc=$rc"
    failures=$((failures + 1))
  elif [[ -n $pattern ]] && ! grep -qF -- "$pattern" <<<"$out"; then
    echo "FAIL [${envassign:-<unset>} $*]: output lacks '$pattern'"
    failures=$((failures + 1))
  else
    echo "ok   [${envassign:-<unset>} $*]"
  fi
}

expect ok   "DRIVER=openstack ROLE=molecule_openstack" ""
expect ok   "DRIVER=openstack ROLE=molecule_openstack" "MOLECULE_DRIVER="
expect ok   "DRIVER=docker ROLE=molecule_docker"       "MOLECULE_DRIVER=docker"
expect ok   "DRIVER=kubevirt ROLE=molecule_kubevirt"   "MOLECULE_DRIVER=docker" -e molecule_generic_driver=kubevirt
expect fail "docker, kubevirt, openstack"              "MOLECULE_DRIVER=bogus"
expect fail ""                                         "MOLECULE_DRIVER=Docker"

if ((failures)); then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
