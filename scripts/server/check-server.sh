#!/usr/bin/env bash
# Report Nidrew server readiness: the account and checkout, Nix and its
# configuration and packages, and the Harmonia cache. Runs every check even
# after a failure, then summarizes. Run as root (through sudo). Changes
# nothing except the temporary test stores and builds the checks use; never
# prints the signing key.
set -u

port=5000
script_dir=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage: sudo bash check-server.sh [--port PORT]

Run check-account.sh, check-nix-config.sh (which runs check-nix.sh), and
check-harmonia.sh, then print one line per check.

  --port PORT   Cache port (default: 5000)

Exit status: 0 when every check passed, 1 otherwise, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --port)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      port=$2
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

if [ "$(id -u)" -ne 0 ]; then
  printf 'The server checks read protected state and must run as root. As an administrator, run:\n' >&2
  printf '  sudo bash %s --port %s\n' "$script_dir/check-server.sh" "$port" >&2
  exit 1
fi

cd / || exit 1
summary=()
failures=0

# run_check LABEL SCRIPT ARGS...
run_check() {
  local label=$1 script=$2
  shift 2
  printf '\n== %s (%s)\n' "$label" "$(basename "$script")"
  if bash "$script" "$@"; then
    summary+=("[ ok ] $label")
  else
    summary+=("[FAIL] $label: see the output of $(basename "$script") above")
    failures=$((failures + 1))
  fi
}

run_check "account and checkout" "$script_dir/check-account.sh"
run_check "nix configuration" "$script_dir/check-nix-config.sh"
run_check "harmonia cache" "$script_dir/check-harmonia.sh" --port "$port"

printf '\n== Summary\n'
printf '%s\n' "${summary[@]}"
if [ $failures -eq 0 ]; then
  printf 'Server ready.\n'
  exit 0
fi
printf 'Server not ready: %s of %s checks failed.\n' "$failures" "${#summary[@]}"
exit 1
