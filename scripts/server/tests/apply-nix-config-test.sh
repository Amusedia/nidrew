#!/usr/bin/env bash
# Tests for apply-nix-config.sh managing files in temporary directories with
# --files-only. Needs Nix for validation; activation as root is verified on the
# host, see work/server-setup/journal-2.md.
# Usage: scripts/server/tests/apply-nix-config-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
apply="$repo_dir/scripts/server/apply-nix-config.sh"
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

flake="$work/flake"
etc="$work/etc"
state="$work/state"
reset() {
  rm -rf "$flake" "$etc" "$state"
  mkdir -p "$flake" "$etc"
  cp "$repo_dir/nix/server/flake.nix" "$repo_dir/nix/server/flake.lock" \
    "$repo_dir/nix/server/nidrew.conf" "$flake/"
  printf 'build-users-group = nixbld\n' >"$etc/nix.conf"
}
run_apply() {
  output=$(bash "$apply" --files-only --flake-dir "$flake" --nix-conf-dir "$etc" \
    --state-dir "$state" "$@" 2>&1)
  status=$?
}
snapshot() { (cd "$work" && find etc state -type f -exec sha256sum {} + 2>/dev/null | sort); }

output=$(bash "$apply" --bogus 2>&1)
status=$?
expect "unknown argument is a usage error" 2 "Usage:"

if [ "$(id -u)" -ne 0 ]; then
  output=$(bash "$apply" 2>&1)
  status=$?
  expect "non-root default invocation prints the sudo command" 1 "sudo bash $apply"
  output=$(bash "$repo_dir/scripts/server/check-nix-config.sh" 2>&1)
  status=$?
  expect "check-nix-config requires root" 1 "sudo bash"
else
  printf 'skip: non-root invocation (running as root)\n'
fi

if ! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  printf 'skip: file management tests need Nix\n'
  printf '\n%s passed, %s failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
  exit
fi
rev=$(sed -n 's/.*"rev": "\([0-9a-f]*\)".*/\1/p' "$repo_dir/nix/server/flake.lock" | head -n 1)

reset
run_apply
expect "fresh apply succeeds" 0 "installed $etc/nidrew.conf"
cmp -s "$etc/nidrew.conf" "$flake/nidrew.conf" && pass "nidrew.conf matches the template" ||
  fail "nidrew.conf matches the template"
grep -q "\"rev\":\"$rev\"" "$etc/registry.json" && pass "registry pins the locked revision" ||
  fail "registry pins the locked revision"
[ "$(cat "$etc/nix.conf")" = "$(printf 'build-users-group = nixbld\ninclude nidrew.conf')" ] &&
  pass "nix.conf keeps its content and gains one include" || fail "nix.conf keeps its content and gains one include"
grep -qx 'build-users-group = nixbld' "$state/previous/nix.conf" 2>/dev/null &&
  pass "previous nix.conf is retained" || fail "previous nix.conf is retained"
grep -q " $etc/nidrew.conf\$" "$state/managed.sha256" 2>/dev/null &&
  pass "checksums are recorded" || fail "checksums are recorded"

before=$(snapshot)
run_apply
expect "matching rerun reports no change" 0 "unchanged $etc/nidrew.conf"
[ "$(snapshot)" = "$before" ] && pass "matching rerun changes no file" || fail "matching rerun changes no file"

printf 'sandbox = false\n' >>"$etc/nidrew.conf"
before=$(snapshot)
run_apply
expect "local edit is refused" 1 "edited locally"
[ "$(snapshot)" = "$before" ] && pass "local edit is preserved" || fail "local edit is preserved"

reset
run_apply >/dev/null
printf '# revised template\n' >>"$flake/nidrew.conf"
run_apply
expect "unchanged managed file is updated" 0 "updated $etc/nidrew.conf"
cmp -s "$etc/nidrew.conf" "$flake/nidrew.conf" && pass "update installs the new template" ||
  fail "update installs the new template"
[ -f "$state/previous/nidrew.conf" ] && ! grep -q 'revised' "$state/previous/nidrew.conf" &&
  pass "update retains the previous file" || fail "update retains the previous file"

reset
printf 'sandbox = false\n' >>"$etc/nix.conf"
before=$(snapshot)
run_apply
expect "conflicting nix.conf setting is refused" 1 "sets sandbox"
[ "$(snapshot)" = "$before" ] && [ ! -e "$etc/nidrew.conf" ] &&
  pass "conflict changes nothing" || fail "conflict changes nothing"

reset
printf '{"version":2,"flakes":[]}\n' >"$etc/registry.json"
run_apply
expect "unexpected existing file is refused" 1 "not managed by Nidrew"
grep -qx '{"version":2,"flakes":\[\]}' "$etc/registry.json" && pass "unexpected file is preserved" ||
  fail "unexpected file is preserved"

reset
cp "$flake/nidrew.conf" "$etc/nidrew.conf"
run_apply
expect "resume accepts a matching unrecorded file" 0 "unchanged $etc/nidrew.conf"

reset
printf 'bogus-setting = 1\n' >>"$flake/nidrew.conf"
run_apply
expect "invalid settings are refused before activation" 1 "unknown setting"
[ ! -e "$etc/nidrew.conf" ] && ! grep -q include "$etc/nix.conf" &&
  pass "invalid settings are not installed" || fail "invalid settings are not installed"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
