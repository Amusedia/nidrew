#!/usr/bin/env bash
# Report the multi-user Nix installation: pinned version, daemon units, build
# users, trust settings, and a sandboxed build as nidrew through the daemon.
# Run as root (through sudo). Changes nothing except adding the small test
# build output to the Nix store.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
release_file=$script_dir/nix-release.conf
account=nidrew
home=/home/nidrew
profile_bin=/nix/var/nix/profiles/default/bin
failures=0

usage() {
  cat <<'EOF'
Usage: sudo bash check-nix.sh [--release-file PATH]

  --release-file PATH   Pinned release (default: nix-release.conf beside this script)

Exit status: 0 when Nix is ready, 1 when a check fails, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --release-file)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      release_file=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

report() { printf '[%s] %s: %s\n' "$1" "$2" "$3"; }
ok() { report ' ok ' "$1" "$2"; }
fail() {
  report 'FAIL' "$1" "$2"
  failures=$((failures + 1))
}
nix_cmd() { "$profile_bin/nix" --extra-experimental-features nix-command "$@"; }
as_account() {
  runuser -u "$account" -- env HOME="$home" PATH="$profile_bin:/usr/bin:/bin" "$@"
}

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run as root to inspect the Nix installation: sudo bash %s\n' "$0" >&2
  exit 1
fi
cd / || exit 1

version=$(sed -n 's/^NIX_VERSION=//p' "$release_file" 2>/dev/null | tail -n 1)
if [ ! -x "$profile_bin/nix" ]; then
  fail nix "$profile_bin/nix not found; run bootstrap-nix.sh"
  printf '\nResult: %s problem(s) found\n' "$failures"
  exit 1
fi
installed=$("$profile_bin/nix" --version | awk '{print $NF}')
if [ "$installed" = "$version" ]; then
  ok version "Nix $installed (pinned in $release_file)"
else
  fail version "Nix $installed installed, $release_file pins ${version:-nothing}"
fi

for unit in nix-daemon.socket nix-daemon.service; do
  enabled=$(systemctl is-enabled "$unit" 2>/dev/null)
  active=$(systemctl is-active "$unit" 2>/dev/null)
  report_line="$unit is ${enabled:-unknown}, ${active:-unknown}"
  case "$unit:$enabled:$active" in
    nix-daemon.socket:enabled:active | nix-daemon.service:linked:*) ok daemon "$report_line" ;;
    *) fail daemon "$report_line; expected the socket enabled and active, the service linked" ;;
  esac
done

group_line=$(getent group nixbld)
if [ -n "$group_line" ]; then
  members=$(printf '%s\n' "$group_line" | cut -d: -f4 | tr ',' '\n' | grep -c .)
  ok "build users" "group nixbld (gid $(printf '%s' "$group_line" | cut -d: -f3)) with $members members"
else
  fail "build users" "group nixbld does not exist"
fi
build_group=$(nix_cmd config show build-users-group 2>/dev/null)
[ "$build_group" = nixbld ] && ok "build users" "build-users-group = nixbld" ||
  fail "build users" "build-users-group is '${build_group}', expected nixbld"

trusted=$(nix_cmd config show trusted-users 2>/dev/null)
[ "$trusted" = root ] && ok trust "trusted-users = root" ||
  fail trust "trusted-users is '$trusted', expected root only"
ok sandbox "sandbox = $(nix_cmd config show sandbox 2>/dev/null)"

if ! id "$account" >/dev/null 2>&1; then
  fail account "$account does not exist; run provision-account.sh"
else
  case " $(id -nG "$account") " in
    *" nixbld "*) fail account "$account is in group nixbld" ;;
  esac
  info=$(as_account nix --extra-experimental-features nix-command store info 2>&1)
  if printf '%s\n' "$info" | grep -qx 'Store URL: daemon' &&
    printf '%s\n' "$info" | grep -qx 'Trusted: 0'; then
    ok daemon "$account uses the daemon store and is not trusted"
  else
    fail daemon "unexpected store info for $account: $(printf '%s' "$info" | tr '\n' ';')"
  fi
  # A unique attribute makes the daemon build instead of reusing an output.
  expr=$(printf 'derivation { name = "nidrew-nix-check"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ok > $out" ]; nonce = "%s"; }' "$(date +%s%N)")
  if out=$(as_account nix-build --no-out-link --quiet -E "$expr" 2>&1) &&
    [ "$(cat "$out" 2>/dev/null)" = ok ]; then
    ok build "$account built $out without sudo"
  else
    fail build "build as $account failed: $out"
  fi
  if runuser -l "$account" -c 'command -v nix' >/dev/null 2>&1; then
    ok profile "nix is on $account's login PATH"
  else
    report 'warn' profile "nix is not on $account's login PATH; use $profile_bin/nix"
  fi
fi

printf '\n'
if [ $failures -gt 0 ]; then
  printf 'Result: %s problem(s) found\n' "$failures"
  exit 1
fi
printf 'Result: Nix %s is ready\n' "$installed"
