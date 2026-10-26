#!/usr/bin/env bash
# Run the complete Nidrew server setup in order: the nidrew account and
# checkout, multi-user Nix, the server Nix configuration and packages, and
# Harmonia. Run as root (through sudo) from the source checkout. Provisioning
# selects the revision; the later steps run from the server checkout at that
# revision. Each step keeps matching state, so a rerun resumes after a failure
# or interruption.
set -u

checkout=/home/nidrew/nidrew
source_path=/mnt/c/projects/nidrew
revision=HEAD
port=5000
key_name=
script_dir=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage: sudo bash setup-server.sh [--source PATH] [--revision REV] [--port PORT]
                                 [--key-name NAME]

Run, in order and stopping at the first failure:
  1. provision-account.sh  account, storage, and checkout at REV (from here)
  2. bootstrap-nix.sh      pinned multi-user Nix (from the server checkout)
  3. apply-nix-config.sh   server Nix settings, registry, and packages
  4. setup-harmonia.sh     Harmonia, its signing key, and port restrictions
Each step runs its own checks. Rerun after resolving a failure.

  --source PATH    Source Git repository (default: /mnt/c/projects/nidrew)
  --revision REV   Committed revision to select (default: HEAD)
  --port PORT      Cache port (default: 5000)
  --key-name NAME  Name for a newly generated signing key
  --checkout DIR   Server checkout (default: /home/nidrew/nidrew; for tests)

Exit status: 0 when every step succeeded, 1 when a step was refused or
failed, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --source | --revision | --port | --key-name | --checkout)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      case $1 in
        --source) source_path=$2 ;;
        --revision) revision=$2 ;;
        --port) port=$2 ;;
        --key-name) key_name=$2 ;;
        --checkout) checkout=$2 ;;
      esac
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

if ! [[ $port =~ ^[1-9][0-9]{0,4}$ ]] || [ "$port" -gt 65535 ]; then
  printf 'Invalid port: %s\n' "$port" >&2
  usage >&2
  exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
  printf 'Server setup creates accounts and system services and must run as root. As an administrator, run:\n' >&2
  printf '  sudo bash %s --source %s --revision %s\n' "$script_dir/setup-server.sh" "$source_path" "$revision" >&2
  exit 1
fi

names=("account and checkout" "multi-user Nix" "Nix configuration and packages" "Harmonia cache")
total=${#names[@]}

# run_step N SCRIPT ARGS...: run one step, stopping setup when it fails.
run_step() {
  local number=$1 script=$2
  shift 2
  printf '\n== Step %s of %s: %s (%s)\n' "$number" "$total" "${names[$((number - 1))]}" "$(basename "$script")"
  if [ ! -f "$script" ]; then
    printf '\nSetup stopped at step %s of %s (%s): %s is missing.\n' "$number" "$total" \
      "${names[$((number - 1))]}" "$script" >&2
    exit 1
  fi
  bash "$script" "$@" && return 0
  printf '\nSetup stopped at step %s of %s (%s). Completed steps are kept; resolve the message above and rerun:\n' \
    "$number" "$total" "${names[$((number - 1))]}" >&2
  printf '  sudo bash %s --source %s --revision %s --port %s%s\n' "$script_dir/setup-server.sh" \
    "$source_path" "$revision" "$port" "${key_name:+ --key-name $key_name}" >&2
  exit 1
}

cd / || exit 1
run_step 1 "$script_dir/provision-account.sh" --source "$source_path" --revision "$revision"
steps=$checkout/scripts/server
run_step 2 "$steps/bootstrap-nix.sh"
run_step 3 "$steps/apply-nix-config.sh"
harmonia_args=(--port "$port")
[ -z "$key_name" ] || harmonia_args+=(--key-name "$key_name")
run_step 4 "$steps/setup-harmonia.sh" "${harmonia_args[@]}"

selected=$(git -c safe.directory="$checkout" -C "$checkout" rev-parse --verify --quiet refs/nidrew/selected 2>/dev/null || true)
printf '\nServer setup complete%s. Check readiness with:\n' "${selected:+ at $selected}"
printf '  sudo bash %s --port %s\n' "$steps/check-server.sh" "$port"
