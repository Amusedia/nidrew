#!/usr/bin/env bash
# Tests for scripts/server/harmonia/firewall.sh with stub nft, ip, wslinfo,
# and sleep commands. The rules themselves are verified on the host by
# check-harmonia.sh, see work/server-setup/journal-2.md.
# Usage: scripts/server/tests/harmonia-firewall-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
firewall="$repo_dir/scripts/server/harmonia/firewall.sh"
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
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

stubs="$work/bin"
mkdir -p "$stubs"
cat >"$stubs/nft" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/nft.args"
[ "\$1" != -f ] || cat >>"$work/nft.rules"
EOF
cat >"$stubs/ip" <<EOF
#!/bin/sh
[ -n "\${STUB_GATEWAY:-}" ] && printf 'default via %s dev eth0 proto kernel onlink\n' "\$STUB_GATEWAY"
exit 0
EOF
cat >"$stubs/wslinfo" <<'EOF'
#!/bin/sh
printf '%s\n' "${STUB_MODE:-nat}"
EOF
printf '#!/bin/sh\n' >"$stubs/sleep"
chmod +x "$stubs"/*

run_firewall() {
  rm -f "$work/nft.args" "$work/nft.rules"
  output=$(PATH="$stubs:$PATH" sh "$firewall" "$@" 2>&1)
  status=$?
}

STUB_GATEWAY=172.30.208.1 run_firewall start 5000
expect "start loads the rules" 0 "allowed from loopback and 172.30.208.1"
rules=$(cat "$work/nft.rules" 2>/dev/null)
check "rules replace only the Nidrew table" \
  'printf "%s\n" "$rules" | grep -qx "delete table inet nidrew_harmonia" && ! printf "%s\n" "$rules" | grep -q "flush ruleset"'
check "IPv4 is allowed from loopback and the gateway only" \
  'printf "%s\n" "$rules" | grep -qF "tcp dport 5000 ip saddr { 127.0.0.0/8, 172.30.208.1 } accept"'
check "IPv6 is allowed from loopback only" 'printf "%s\n" "$rules" | grep -qF "tcp dport 5000 ip6 saddr ::1 accept"'
check "every other source is dropped" 'printf "%s\n" "$rules" | grep -qF "tcp dport 5000 counter drop"'

STUB_GATEWAY=172.30.208.1 run_firewall start 5001
check "the port is configurable" 'grep -qF "tcp dport 5001 counter drop" "$work/nft.rules"'

STUB_GATEWAY=172.30.208.1 STUB_MODE=mirrored run_firewall start 5000
expect "mirrored networking is refused" 1 "mirrored"
check "refusal loads no rules" '[ ! -e "$work/nft.args" ]'

run_firewall start 5000
expect "a missing default route fails" 1 "no IPv4 default route"
check "missing route loads no rules" '[ ! -e "$work/nft.args" ]'

STUB_GATEWAY=172.30.208.1 run_firewall start 50000x
expect "an invalid port is a usage error" 2 "Usage:"

run_firewall stop
expect "stop removes the Nidrew table" 0 "removed"
check "stop deletes only the Nidrew table" 'grep -qx "delete table inet nidrew_harmonia" "$work/nft.args"'

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
