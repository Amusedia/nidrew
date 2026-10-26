#!/usr/bin/env bash
# Tests for cache-endpoint.sh with stub systemctl and ip commands and a
# temporary public key.
# Usage: scripts/server/tests/cache-endpoint-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
endpoint="$repo_dir/scripts/server/cache-endpoint.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0
failed=0
output=
status=0

pass() {
  passed=$((passed + 1))
  printf 'pass: %s\n' "$1"
}
fail() {
  failed=$((failed + 1))
  printf 'FAIL: %s\n%s\n' "$1" "$output"
}
expect() {
  local name=$1 expected_status=$2 expected_text=$3
  if [ "$status" -eq "$expected_status" ] && printf '%s\n' "$output" | grep -qF -- "$expected_text"; then
    pass "$name"
  else
    fail "$name (exit $status)"
  fi
}

stubs="$work/bin"
mkdir -p "$stubs"
cat >"$stubs/systemctl" <<'EOF'
#!/bin/sh
[ -n "${STUB_LISTEN:-}" ] && printf '%s\n' "$STUB_LISTEN"
exit 0
EOF
cat >"$stubs/ip" <<'EOF'
#!/bin/sh
[ -n "${STUB_SRC:-}" ] && printf '1.1.1.1 via 172.30.208.1 dev eth0 src %s uid 1000\n    cache\n' "$STUB_SRC"
exit 0
EOF
chmod +x "$stubs"/*
key="$work/public-key"
printf 'test-cache-1:AAAA\n' >"$key"

run_endpoint() {
  output=$(PATH="$stubs:$PATH" bash "$endpoint" --public-key "$key" "$@" 2>&1)
  status=$?
}

STUB_LISTEN='[::]:5000 (Stream)' STUB_SRC=172.30.217.209 run_endpoint
expect "prints the address" 0 "address=172.30.217.209"
expect "prints the socket port" 0 "port=5000"
expect "prints the endpoint" 0 "endpoint=http://172.30.217.209:5000"
expect "prints the public key" 0 "public_key=test-cache-1:AAAA"

STUB_LISTEN='[::]:5001 (Stream)' STUB_SRC=172.30.217.209 run_endpoint
expect "follows a configured port" 0 "endpoint=http://172.30.217.209:5001"

STUB_LISTEN='127.0.0.1:5000 (Stream)' STUB_SRC=172.30.217.209 run_endpoint
expect "a local-only listener is not published" 1 "127.0.0.1:5000"

STUB_SRC=172.30.217.209 run_endpoint
expect "a missing socket fails" 1 "harmonia.socket"

STUB_LISTEN='[::]:5000 (Stream)' run_endpoint
expect "a missing address fails" 1 "no IPv4 address"

rm "$key"
STUB_LISTEN='[::]:5000 (Stream)' STUB_SRC=172.30.217.209 run_endpoint
expect "a missing public key fails" 1 "$key"

output=$(bash "$endpoint" --bogus 2>&1)
status=$?
expect "unknown argument is a usage error" 2 "Usage:"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
