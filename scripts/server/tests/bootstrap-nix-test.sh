#!/usr/bin/env bash
# Tests for bootstrap-nix.sh and check-nix.sh that run without root on a host
# without Nix. Root behavior is verified on the host; see
# work/server-setup/journal-2.md.
# Usage: scripts/server/tests/bootstrap-nix-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
server_dir=$(cd "$script_dir/.." && pwd)
bootstrap="$server_dir/bootstrap-nix.sh"
check_nix="$server_dir/check-nix.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

check() {
  local name=$1 expected_status=$2 expected_text=$3
  shift 3
  output=$("$@" 2>&1)
  status=$?
  if [ "$status" -eq "$expected_status" ] && printf '%s\n' "$output" | grep -qF -- "$expected_text"; then
    passed=$((passed + 1))
    printf 'pass: %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL: %s (exit %s)\n%s\n' "$name" "$status" "$output"
  fi
}

cat >"$work/release.conf" <<EOF
NIX_VERSION=9.9.9
NIX_INSTALLER_URL=file://$work/never-downloaded
NIX_INSTALLER_SHA256=$(printf '0%.0s' $(seq 64))
EOF

check "unknown argument is a usage error" 2 "Usage:" bash "$bootstrap" --bogus
check "missing release file is reported" 1 "release file" \
  bash "$bootstrap" --release-file "$work/missing.conf"

if [ "$(id -u)" -ne 0 ] && [ ! -e /nix ]; then
  check "non-root invocation prints the sudo command" 1 \
    "sudo bash $bootstrap --release-file $work/release.conf" \
    bash "$bootstrap" --release-file "$work/release.conf"
  check "non-root invocation reports the inspected state" 1 "No Nix installation found" \
    bash "$bootstrap" --release-file "$work/release.conf"
  if printf '%s\n' "$output" | grep -qi download; then
    failed=$((failed + 1))
    printf 'FAIL: non-root invocation does not download\n%s\n' "$output"
  else
    passed=$((passed + 1))
    printf 'pass: non-root invocation does not download\n'
  fi
else
  printf 'skip: non-root invocation tests (running as root or Nix present)\n'
fi

if [ "$(id -u)" -ne 0 ]; then
  check "check-nix requires root" 1 "sudo bash $check_nix" bash "$check_nix"
else
  printf 'skip: check-nix requires root (running as root)\n'
fi

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
