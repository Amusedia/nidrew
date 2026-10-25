#!/usr/bin/env bash
# Tests for provision-account.sh that run without root. Root behavior is
# verified on the host; see work/server-setup/journal-2.md.
# Usage: scripts/server/tests/provision-account-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
provision="$(cd "$script_dir/.." && pwd)/provision-account.sh"
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

if [ "$(id -u)" -ne 0 ]; then
  check "non-root invocation prints the sudo command" 1 \
    "sudo bash $provision --source /src --revision main" \
    bash "$provision" --source /src --revision main
else
  printf 'skip: non-root invocation prints the sudo command (running as root)\n'
fi

check "unknown argument is a usage error" 2 "Usage:" bash "$provision" --bogus

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
