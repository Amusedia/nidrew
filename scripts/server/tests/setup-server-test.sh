#!/usr/bin/env bash
# Tests for setup-server.sh and check-server.sh with stub step scripts. Root
# is simulated with an id stub; the real steps are verified on the host; see
# work/server-setup/journal-2.md.
# Usage: scripts/server/tests/setup-server-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
server_dir=$(cd "$script_dir/.." && pwd)
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

# check_log NAME EXPECTED: the step log equals EXPECTED (one call per line).
check_log() {
  local name=$1 expected=$2 actual
  actual=$(cat "$log" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    passed=$((passed + 1))
    printf 'pass: %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\nexpected:\n%s\nactual:\n%s\n' "$name" "$expected" "$actual"
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
log=$work/log
src=$work/src
checkout=$work/checkout
mkdir -p "$src" "$checkout/scripts/server" "$work/bin"
cp "$server_dir/setup-server.sh" "$server_dir/check-server.sh" "$src/"
cp "$server_dir/check-server.sh" "$checkout/scripts/server/"

# Stub steps log "<dir> <name> <args>" and exit with $FAIL_<name> or 0.
stub() {
  local dir=$1 name=$2 var
  var=FAIL_$(printf '%s' "$name" | tr '-' '_')
  cat >"$dir/$name.sh" <<EOF
#!/usr/bin/env bash
printf '%s %s %s\n' "\$(basename "\$(dirname "\$0")")" $name "\$*" | sed 's/ *\$//' >>"$log"
printf 'stub $name ran\n'
exit \${$var:-0}
EOF
}
stub "$src" provision-account
for name in bootstrap-nix apply-nix-config setup-harmonia check-account check-nix-config check-harmonia; do
  stub "$checkout/scripts/server" "$name"
done
cat >"$work/bin/id" <<'EOF'
#!/bin/sh
if [ "$1" = -u ] && [ $# -eq 1 ]; then echo 0; exit 0; fi
exec /usr/bin/id "$@"
EOF
chmod +x "$work/bin/id"

as_root() { PATH="$work/bin:$PATH" "$@"; }
setup() { as_root bash "$src/setup-server.sh" --checkout "$checkout" "$@"; }
check_server() { as_root bash "$checkout/scripts/server/check-server.sh" "$@"; }

# setup-server.sh
if [ "$(id -u)" -ne 0 ]; then
  check "non-root setup prints the sudo command" 1 \
    "sudo bash $src/setup-server.sh --source /src --revision main" \
    bash "$src/setup-server.sh" --source /src --revision main
fi
check "unknown setup argument is a usage error" 2 "Usage:" setup --bogus
check "invalid port is a usage error" 2 "Usage:" setup --port 0

: >"$log"
check "setup runs every step and reports completion" 0 "Server setup complete" \
  setup --source /src --revision abc123 --port 5001 --key-name k-1
check_log "provisioning runs from the source, later steps from the checkout" \
  "src provision-account --source /src --revision abc123
server bootstrap-nix
server apply-nix-config
server setup-harmonia --port 5001 --key-name k-1"

: >"$log"
check "default setup passes the default port and no key name" 0 "Server setup complete" setup
check_log "default arguments" \
  "src provision-account --source /mnt/c/projects/nidrew --revision HEAD
server bootstrap-nix
server apply-nix-config
server setup-harmonia --port 5000"

: >"$log"
check "a failed step stops setup and names it" 1 "stopped at step 3 of 4 (Nix configuration" \
  env FAIL_apply_nix_config=1 bash -c "PATH='$work/bin':\$PATH bash '$src/setup-server.sh' --checkout '$checkout'"
check_log "steps after the failure do not run" \
  "src provision-account --source /mnt/c/projects/nidrew --revision HEAD
server bootstrap-nix
server apply-nix-config"

: >"$log"
check "a rerun after a failure resumes and completes" 0 "Server setup complete" setup

rm "$checkout/scripts/server/bootstrap-nix.sh"
check "a checkout without the step scripts is refused" 1 "bootstrap-nix.sh" setup
stub "$checkout/scripts/server" bootstrap-nix

# check-server.sh
if [ "$(id -u)" -ne 0 ]; then
  check "non-root check prints the sudo command" 1 "sudo bash" \
    bash "$checkout/scripts/server/check-server.sh"
fi
check "unknown check argument is a usage error" 2 "Usage:" check_server --bogus

: >"$log"
check "all checks passing reports the server ready" 0 "Server ready" check_server --port 5001
check_log "checks run in order with the port" \
  "server check-account
server check-nix-config
server check-harmonia --port 5001"

: >"$log"
check "a failing check is reported by name and fails the run" 1 "[FAIL] nix configuration" \
  env FAIL_check_nix_config=1 bash -c "PATH='$work/bin':\$PATH bash '$checkout/scripts/server/check-server.sh'"
check_log "later checks still run after a failure" \
  "server check-account
server check-nix-config
server check-harmonia --port 5000"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
