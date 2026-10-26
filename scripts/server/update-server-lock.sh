#!/usr/bin/env bash
# Deliberately update the server nixpkgs pin in nix/server/flake.lock and
# report the old and new revisions and tool versions. Run as an ordinary user
# in the source checkout; never run by setup. Agent pins are not touched.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
flake_dir=$script_dir/../../nix/server

usage() {
  cat <<'EOF'
Usage: update-server-lock.sh [--flake-dir DIR]

Update the nixpkgs input of the server flake to the newest commit of the
branch in flake.nix, then print the next steps: review, commit, sync the
server checkout, apply, check, and record the result in the work journal.

  --flake-dir DIR   Server flake (default: nix/server in this checkout)

Exit status: 0 when updated or already current, 1 on failure, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --flake-dir)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      flake_dir=$2
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

nix_cmd() { nix --extra-experimental-features 'nix-command flakes' "$@"; }
command -v nix >/dev/null 2>&1 || {
  printf 'Nix is not on PATH\n' >&2
  exit 1
}
flake_dir=$(cd "$flake_dir" && pwd) || exit 1
summary() {
  printf 'nixpkgs %s, harmonia %s, skopeo %s, nftables %s\n' \
    "$(sed -n 's/.*"rev": "\([0-9a-f]*\)".*/\1/p' "$flake_dir/flake.lock" | head -n 1)" \
    "$(nix_cmd eval --raw "path:$flake_dir#harmonia.version")" \
    "$(nix_cmd eval --raw "path:$flake_dir#skopeo.version")" \
    "$(nix_cmd eval --raw "path:$flake_dir#nftables.version")"
}

before=$(summary) || exit 1
nix_cmd flake update --flake "path:$flake_dir" || exit 1
after=$(summary) || exit 1
printf 'Before: %s\nAfter:  %s\n' "$before" "$after"
if [ "$before" = "$after" ]; then
  printf 'The lock is already current.\n'
  exit 0
fi
cat <<EOF

Next steps:
  1. Review and commit $flake_dir/flake.lock.
  2. As an administrator: sudo -u nidrew -i bash /home/nidrew/nidrew/scripts/server/sync-checkout.sh --revision <commit>
  3. As an administrator: sudo bash /home/nidrew/nidrew/scripts/server/apply-nix-config.sh
  4. Record the versions above and the check results in the work journal.
EOF
