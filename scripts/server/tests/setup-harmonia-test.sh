#!/usr/bin/env bash
# Tests for setup-harmonia.sh managing the signing key and files in temporary
# directories with --files-only. Needs Nix for key handling; the account,
# service activation, and serving are verified on the host, see
# work/server-setup/journal-2.md.
# Usage: scripts/server/tests/setup-harmonia-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
setup="$repo_dir/scripts/server/setup-harmonia.sh"
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

etc="$work/etc"
units="$work/units"
state="$work/state"
reset() {
  rm -rf "$etc" "$units" "$state"
  mkdir -p "$units"
}
run_setup() {
  output=$(bash "$setup" --files-only --harmonia-dir "$etc" --unit-dir "$units" \
    --state-dir "$state" "$@" 2>&1)
  status=$?
}
snapshot() { (cd "$work" && find etc units state -type f -exec sha256sum {} + 2>/dev/null | sort); }

output=$(bash "$setup" --bogus 2>&1)
status=$?
expect "unknown argument is a usage error" 2 "Usage:"

if [ "$(id -u)" -ne 0 ]; then
  output=$(bash "$setup" 2>&1)
  status=$?
  expect "non-root default invocation prints the sudo command" 1 "sudo bash $setup"
  output=$(bash "$repo_dir/scripts/server/check-harmonia.sh" 2>&1)
  status=$?
  expect "check-harmonia requires root" 1 "sudo bash"
else
  printf 'skip: non-root invocation (running as root)\n'
fi

if ! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  printf 'skip: key and file tests need Nix\n'
  printf '\n%s passed, %s failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
  exit
fi
nix_bin=/nix/var/nix/profiles/default/bin/nix
[ -x "$nix_bin" ] || nix_bin=$(command -v nix)
public_of() { "$nix_bin" --extra-experimental-features nix-command key convert-secret-to-public <"$1"; }

reset
run_setup --key-name test-cache-1
expect "fresh setup generates a signing key" 0 "generated $etc/secret-key"
check "secret key has mode 600" '[ "$(stat -c %a "$etc/secret-key")" = 600 ]'
check "public key matches the secret key" '[ "$(public_of "$etc/secret-key")" = "$(cat "$etc/public-key")" ]'
check "public key uses the key name" 'grep -q "^test-cache-1:" "$etc/public-key"'
check "public key has mode 644" '[ "$(stat -c %a "$etc/public-key")" = 644 ]'
check "output publishes the public key" 'printf "%s\n" "$output" | grep -qF "$(cat "$etc/public-key")"'
secret_value=$(cut -d: -f2 "$etc/secret-key")
check "output does not contain the secret key" '! printf "%s\n" "$output" | grep -qF "$secret_value"'
for file in "$etc/harmonia.toml" "$units/harmonia.service" "$units/harmonia.socket"; do
  check "installs ${file##*/}" 'cmp -s "$file" "$repo_dir/scripts/server/harmonia/${file##*/}"'
done
check "unit and config checksums are recorded" \
  'grep -q " $units/harmonia.service\$" "$state/managed.sha256" && grep -q " $etc/harmonia.toml\$" "$state/managed.sha256"'
check "service file holds only the key reference" '! grep -qF "$secret_value" "$units/harmonia.service"'

before=$(snapshot)
run_setup --key-name other-name-1
expect "matching rerun keeps the existing key" 0 "kept $etc/secret-key"
check "matching rerun changes no file" '[ "$(snapshot)" = "$before" ]'

printf 'other-1:AAAA\n' >"$etc/public-key"
before=$(snapshot)
run_setup
expect "mismatched public key is refused" 1 "does not match"
check "mismatched public key is preserved" '[ "$(snapshot)" = "$before" ]'

reset
run_setup >/dev/null
rm "$etc/public-key"
run_setup
expect "missing public key is derived again" 0 "wrote $etc/public-key"
check "derived public key matches" '[ "$(public_of "$etc/secret-key")" = "$(cat "$etc/public-key")" ]'

chmod 0644 "$etc/secret-key"
run_setup
expect "readable secret key is refused" 1 "mode 644"
chmod 0600 "$etc/secret-key"

printf 'corrupt-secret-value\n' >"$etc/secret-key"
rm "$etc/public-key"
before=$(snapshot)
run_setup
expect "invalid secret key is refused" 1 "not a valid Nix signing key"
check "invalid secret key is preserved" '[ "$(snapshot)" = "$before" ]'
check "invalid secret key value is not printed" '! printf "%s\n" "$output" | grep -qF corrupt-secret-value'

reset
mkdir -p "$etc"
printf 'lost-1:AAAA\n' >"$etc/public-key"
run_setup
expect "public key without secret key is refused" 1 "restore the secret key"
check "no key is generated beside an orphaned public key" '[ ! -e "$etc/secret-key" ]'

reset
run_setup >/dev/null
printf '# local edit\n' >>"$units/harmonia.service"
before=$(snapshot)
run_setup
expect "local unit edit is refused" 1 "edited locally"
check "local unit edit is preserved" '[ "$(snapshot)" = "$before" ]'

reset
run_setup --key-name 'bad name'
expect "invalid key name is refused" 1 "key name"
check "invalid key name creates no key" '[ ! -e "$etc/secret-key" ]'

reset
mkdir -p "$work/flake"
cp "$repo_dir/scripts/server/harmonia/"* "$work/flake/"
printf 'workers = [\n' >>"$work/flake/harmonia.toml"
run_setup --template-dir "$work/flake"
expect "invalid TOML is refused before activation" 1 "harmonia.toml"
check "invalid TOML is not installed" '[ ! -e "$etc/harmonia.toml" ] && [ ! -e "$etc/secret-key" ]'

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
