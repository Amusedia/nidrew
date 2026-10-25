#!/usr/bin/env bash
# Create the nidrew account, its storage, and the server checkout. Run as root
# (through sudo) from the source checkout; rerunning preserves matching state.
# nidrew gets no sudo access; conflicting existing state stops the script.
set -u

account=nidrew
home=/home/nidrew
checkout=$home/nidrew
artifacts=$home/artifacts
source_path=/mnt/c/projects/nidrew
revision=HEAD
script_dir=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage: sudo bash provision-account.sh [--source PATH] [--revision REV]

Create the nidrew account with home /home/nidrew, the artifacts directory
/home/nidrew/artifacts, and the server checkout /home/nidrew/nidrew, then
run sync-checkout.sh as nidrew to clone the source and select REV.

  --source PATH    Source Git repository (default: /mnt/c/projects/nidrew)
  --revision REV   Committed revision to select (default: HEAD)

Exit status: 0 on success, 1 when refused or failed, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --source | --revision)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      if [ "$1" = --source ]; then source_path=$2; else revision=$2; fi
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

refuse() {
  printf 'Refused: %s\n' "$1" >&2
  [ $# -lt 2 ] || printf 'Resolve: %s\n' "$2" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  printf 'This step creates an account and must run as root. As an administrator, run:\n' >&2
  printf '  sudo bash %s --source %s --revision %s\n' "$script_dir/provision-account.sh" "$source_path" "$revision" >&2
  exit 1
fi

# Account.
if id "$account" >/dev/null 2>&1; then
  current_home=$(getent passwd "$account" | cut -d: -f6)
  [ "$current_home" = "$home" ] ||
    refuse "account $account exists with home $current_home, not $home" \
      "change it with 'usermod --home $home --move-home $account' or remove the account"
  printf 'Account %s exists (uid %s).\n' "$account" "$(id -u "$account")"
else
  useradd --create-home --home-dir "$home" --shell /bin/bash --user-group "$account" ||
    refuse "useradd failed for $account"
  printf 'Created account %s (uid %s, password locked).\n' "$account" "$(id -u "$account")"
fi

for group in sudo admin wheel; do
  if id -nG "$account" | tr ' ' '\n' | grep -qx "$group"; then
    refuse "$account is in group $group; routine work must not have general sudo" \
      "remove it with: sudo gpasswd -d $account $group"
  fi
done
if sudo -l -U "$account" 2>/dev/null | grep -q 'may run the following'; then
  refuse "$account has sudo privileges; routine work must not have general sudo" \
    "remove the matching entries from /etc/sudoers or /etc/sudoers.d/"
fi

# Storage: owned by the account, on the Linux filesystem.
ensure_dir() {
  local path=$1 mode=$2 owner
  if [ -e "$path" ]; then
    [ -d "$path" ] && [ ! -L "$path" ] || refuse "$path exists and is not a directory"
    owner=$(stat -c %U:%G "$path")
    [ "$owner" = "$account:$account" ] ||
      refuse "$path is owned by $owner, not $account:$account" \
        "inspect it, then fix with: sudo chown $account:$account $path"
    printf 'Directory %s exists (%s, mode %s).\n' "$path" "$owner" "$(stat -c %a "$path")"
  else
    install -d -o "$account" -g "$account" -m "$mode" "$path" || refuse "could not create $path"
    printf 'Created directory %s (mode %s).\n' "$path" "$mode"
  fi
}
ensure_dir "$home" 0700
ensure_dir "$artifacts" 0750

# Checkout, as the account, from the sync script in this source checkout.
cd / || exit 1
runuser -u "$account" -- env HOME="$home" bash "$script_dir/sync-checkout.sh" \
  --source "$source_path" --checkout "$checkout" --revision "$revision" ||
  refuse "the checkout step did not complete; see the message above"

printf '\nProvisioned %s: groups %s; checkout %s at %s.\n' "$account" \
  "$(id -nG "$account")" "$checkout" \
  "$(runuser -u "$account" -- git -C "$checkout" rev-parse refs/nidrew/selected)"
