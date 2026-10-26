#!/usr/bin/env bash
# Set up Harmonia as the harmonia account serving the Debian Nix store. Creates
# the system account, provisions the cache signing key once in /etc/harmonia,
# installs harmonia.toml, the cache port restrictions, and the harmonia socket
# and service units from scripts/server/harmonia/ for the selected port,
# starts the service, and runs check-harmonia.sh.
# Run as root (through sudo). A valid existing key is always kept; local edits,
# unexpected files, and invalid keys stop the run before anything changes.
set -u
umask 077

script_dir=$(cd "$(dirname "$0")" && pwd)
template_dir=$script_dir/harmonia
harmonia_dir=/etc/harmonia
unit_dir=/etc/systemd/system
state_dir=/var/lib/nidrew
account=harmonia
key_name=nidrew-$(hostname -s)-1
port=5000
files_only=0

usage() {
  cat <<'EOF'
Usage: sudo bash setup-harmonia.sh [options]

Create the harmonia system account, generate the cache signing key unless one
exists, install the Harmonia configuration, the cache port restrictions, and
the systemd units, start the service, and verify with check-harmonia.sh.

  --key-name NAME       Name for a newly generated key
                        (default: nidrew-<hostname>-1); ignored when a key exists
  --port PORT           Cache port (default: 5000); pass it on every rerun
  --template-dir DIR    Templates (default: scripts/server/harmonia)
  --harmonia-dir DIR    Key and configuration directory (default: /etc/harmonia)
  --unit-dir DIR        systemd unit directory (default: /etc/systemd/system)
  --state-dir DIR       Checksums and previous files (default: /var/lib/nidrew)
  --files-only          Manage the key and files only: no account, systemd,
                        or check (for tests)

Exit status: 0 when set up and verified, 1 when refused or failed, 2 on usage
errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --key-name | --port | --template-dir | --harmonia-dir | --unit-dir | --state-dir)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      case $1 in
        --key-name) key_name=$2 ;;
        --port) port=$2 ;;
        --template-dir) template_dir=$2 ;;
        --harmonia-dir) harmonia_dir=$2 ;;
        --unit-dir) unit_dir=$2 ;;
        --state-dir) state_dir=$2 ;;
      esac
      shift 2
      ;;
    --files-only)
      files_only=1
      shift
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

case $port in
  '' | *[!0-9]* | 0*) port=0 ;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  printf 'Invalid port: use a number from 1 to 65535\n' >&2
  usage >&2
  exit 2
fi

refuse() {
  printf 'Refused: %s\n' "$1" >&2
  [ $# -lt 2 ] || printf 'Resolve: %s\n' "$2" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ] && { [ $files_only -eq 0 ] || [ "$harmonia_dir" = /etc/harmonia ]; }; then
  printf 'Setting up Harmonia must run as root. As an administrator, run:\n' >&2
  printf '  sudo bash %s\n' "$script_dir/setup-harmonia.sh" >&2
  exit 1
fi

nix_bin=/nix/var/nix/profiles/default/bin/nix
[ -x "$nix_bin" ] || nix_bin=$(command -v nix 2>/dev/null) ||
  refuse "Nix is not installed" "run bootstrap-nix.sh first"
nix_cmd() { "$nix_bin" --extra-experimental-features nix-command "$@"; }
harmonia_bin=/nix/var/nix/profiles/nidrew-server/bin/harmonia-cache
[ $files_only -eq 1 ] || [ -x "$harmonia_bin" ] ||
  refuse "$harmonia_bin is missing" "run apply-nix-config.sh first"

template_dir=$(cd "$template_dir" 2>/dev/null && pwd) || refuse "cannot open the template directory"
templates="harmonia.toml firewall.sh harmonia-firewall.service harmonia.socket harmonia.service"
units="harmonia-firewall.service harmonia.socket harmonia.service"
for file in $templates; do
  [ -r "$template_dir/$file" ] || refuse "cannot read $template_dir/$file"
done

# shellcheck source=managed-files.sh
. "$script_dir/managed-files.sh"

work=$(mktemp -d) || refuse "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT
# Candidates are the templates with the selected port.
mkdir "$work/rendered"
for file in $templates; do
  sed "s/@PORT@/$port/g" "$template_dir/$file" >"$work/rendered/$file" || refuse "cannot render $file"
done
rendered=$work/rendered
owner=$(id -u)
secret=$harmonia_dir/secret-key
public=$harmonia_dir/public-key

# Plan every step before changing anything.
if [ -e "$harmonia_dir" ] || [ -L "$harmonia_dir" ]; then
  [ -d "$harmonia_dir" ] && [ ! -L "$harmonia_dir" ] && [ "$(stat -c %u "$harmonia_dir")" = "$owner" ] &&
    [ $((0$(stat -c %a "$harmonia_dir") & 022)) -eq 0 ] ||
    refuse "$harmonia_dir must be a directory owned by $(id -un) and writable only by its owner" \
      "inspect it and fix with: sudo chown root:root $harmonia_dir && sudo chmod 0755 $harmonia_dir"
fi

# The signing key: keep a valid one, generate one only when none exists.
key_action=
if [ -e "$secret" ] || [ -L "$secret" ]; then
  [ -f "$secret" ] && [ ! -L "$secret" ] ||
    refuse "$secret is not a regular file" "inspect it; restore the key from a backup as a regular file"
  [ "$(stat -c %u "$secret")" = "$owner" ] ||
    refuse "$secret is owned by $(stat -c %U "$secret"), not $(id -un)" \
      "inspect it, then fix with: sudo chown root:root $secret"
  mode=$(stat -c %a "$secret")
  [ "$mode" = 600 ] ||
    refuse "$secret has mode $mode; other accounts may have read the signing key" \
      "fix with 'sudo chmod 0600 $secret'; rotate the key if untrusted accounts could read it"
  nix_cmd key convert-secret-to-public <"$secret" >"$work/public-key" 2>/dev/null ||
    refuse "$secret is not a valid Nix signing key; it is preserved" \
      "restore the key from a backup, or move it aside to generate a new key and update consumers"
  key_action=kept
else
  [ ! -e "$public" ] ||
    refuse "$public exists without $secret; the signing key may have been lost" \
      "restore the secret key from a backup as $secret (mode 0600), or remove $public to generate a new key and update consumers"
  printf '%s' "$key_name" | grep -qE '^[A-Za-z0-9._-]+$' ||
    refuse "invalid key name '$key_name'" "use letters, digits, '.', '_', and '-' only"
  nix_cmd key generate-secret --key-name "$key_name" >"$work/secret-key" 2>"$work/key.err" &&
    nix_cmd key convert-secret-to-public <"$work/secret-key" >"$work/public-key" 2>>"$work/key.err" ||
    refuse "cannot generate a signing key: $(cat "$work/key.err")"
  key_action=generated
fi
public_action=unchanged
if [ ! -e "$public" ]; then
  public_action=wrote
elif ! cmp -s "$public" "$work/public-key"; then
  refuse "$public does not match the public key of $secret; both are preserved" \
    "if $secret is the intended key, remove $public and rerun to derive it again"
fi

for file in harmonia.toml firewall.sh; do
  plan_file "$harmonia_dir/$file" "$rendered/$file" "$template_dir/$file"
done
for unit in $units; do
  plan_file "$unit_dir/$unit" "$rendered/$unit" "$template_dir/$unit"
done

if [ $files_only -eq 0 ]; then
  if id "$account" >/dev/null 2>&1; then
    account_action=exists
    uid_min=$(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null)
    [ "$(id -u "$account")" -lt "${uid_min:-1000}" ] ||
      refuse "account $account exists as an ordinary user (uid $(id -u "$account"))" \
        "inspect it; remove it with 'sudo userdel $account' if unused, then rerun"
    [ "$(id -nG "$account")" = "$account" ] ||
      refuse "account $account is in groups $(id -nG "$account"); it needs only its own group" \
        "remove the extra groups with: sudo gpasswd -d $account <group>"
    if sudo -l -U "$account" 2>/dev/null | grep -q 'may run the following'; then
      refuse "account $account has sudo privileges" "remove the matching entries from /etc/sudoers or /etc/sudoers.d/"
    fi
  else
    account_action=create
  fi
fi

if [ $conflicts -gt 0 ]; then
  printf 'Refused: %s conflict(s); nothing was changed.\n' "$conflicts" >&2
  exit 1
fi

# Validate the candidate configuration before activation.
NIDREW_TOML=$rendered/harmonia.toml nix_cmd eval --impure --expr \
  'builtins.fromTOML (builtins.readFile (builtins.getEnv "NIDREW_TOML"))' >/dev/null 2>"$work/toml.err" ||
  refuse "$template_dir/harmonia.toml is not valid TOML; nothing was changed: $(cat "$work/toml.err")"
sh -n "$rendered/firewall.sh" 2>"$work/sh.err" ||
  refuse "$template_dir/firewall.sh is not a valid shell script; nothing was changed: $(cat "$work/sh.err")"
if [ $files_only -eq 0 ]; then
  mkdir "$work/units"
  for unit in $units; do cp "$rendered/$unit" "$work/units/"; done
  chmod 0644 "$work/units/"*
  (cd "$work/units" && systemd-analyze verify $units) \
    >"$work/verify.err" 2>&1 ||
    refuse "the Harmonia units do not validate; nothing was changed: $(cat "$work/verify.err")"
fi

# Activate: account, key, configuration, then the service.
if [ $files_only -eq 0 ] && [ "$account_action" = create ]; then
  useradd --system --user-group --no-create-home --home-dir /nonexistent \
    --shell /usr/sbin/nologin "$account" || refuse "useradd failed for $account"
  printf 'created system account %s (uid %s)\n' "$account" "$(id -u "$account")"
elif [ $files_only -eq 0 ]; then
  printf 'unchanged account %s (uid %s)\n' "$account" "$(id -u "$account")"
fi
install -d -m 0755 "$harmonia_dir" "$unit_dir" || refuse "cannot create $harmonia_dir"
mkdir -p "$state_dir/previous" || refuse "cannot create $state_dir"
if [ "$key_action" = generated ]; then
  # umask 077 keeps the copy at mode 0600; the value is never printed.
  cp "$work/secret-key" "$secret.nidrew-new" && mv -f "$secret.nidrew-new" "$secret" ||
    refuse "cannot write $secret"
fi
printf '%s %s\n' "$key_action" "$secret"
if [ "$public_action" = wrote ]; then
  replace "$public" "$work/public-key"
fi
printf '%s %s\n' "$public_action" "$public"

units_changed=0
config_changed=0
firewall_changed=0
apply_file "$harmonia_dir/harmonia.toml" "$rendered/harmonia.toml"
[ "${action[$harmonia_dir/harmonia.toml]}" = unchanged ] || config_changed=1
apply_file "$harmonia_dir/firewall.sh" "$rendered/firewall.sh"
[ "${action[$harmonia_dir/firewall.sh]}" = unchanged ] || firewall_changed=1
for unit in $units; do
  apply_file "$unit_dir/$unit" "$rendered/$unit"
  [ "${action[$unit_dir/$unit]}" = unchanged ] || units_changed=1
done
printf 'Public key: %s\n' "$(cat "$public")"
[ $files_only -eq 0 ] || exit 0

[ $units_changed -eq 0 ] || systemctl daemon-reload || refuse "systemctl daemon-reload failed"
systemctl enable $units >/dev/null 2>&1 || refuse "cannot enable $units"
# A failed service or socket, for example after the key was missing, keeps
# refusing starts until its failed state is cleared.
systemctl reset-failed $units 2>/dev/null
# The restrictions load before the socket listens; restarting them also stops
# the socket, so it starts again below.
if [ $units_changed -eq 1 ] || [ $firewall_changed -eq 1 ] ||
  [ "$(systemctl is-active harmonia-firewall.service)" != active ]; then
  systemctl restart harmonia-firewall.service ||
    refuse "cannot restrict the cache port" "see: systemctl status harmonia-firewall.service"
  printf 'restarted harmonia-firewall.service\n'
  units_changed=1
fi
if [ $units_changed -eq 1 ] || [ "$(systemctl is-active harmonia.socket)" != active ]; then
  systemctl restart harmonia.socket || refuse "cannot start harmonia.socket; see: systemctl status harmonia.socket"
  printf 'started harmonia.socket\n'
fi
if [ $units_changed -eq 1 ] || [ $config_changed -eq 1 ] || [ "$key_action" = generated ] ||
  [ "$(systemctl is-active harmonia.service)" != active ]; then
  systemctl restart harmonia.service ||
    refuse "harmonia.service did not start" "see: systemctl status harmonia.service; journalctl -u harmonia.service"
  printf 'restarted harmonia.service\n'
fi

printf '\n'
bash "$script_dir/check-harmonia.sh" --port "$port" --harmonia-dir "$harmonia_dir" --unit-dir "$unit_dir" \
  --template-dir "$template_dir" --state-dir "$state_dir"
