#!/usr/bin/env bash
# Report the Harmonia cache: the harmonia account and its store access, the
# signing key's protection, managed files, units and the local listener, and a
# store path served with a signature that verifies against the published public
# key, checked as nidrew. With --restart, restart harmonia.service first to
# show it recovers the key from protected Debian storage. Run as root (through
# sudo). Never prints the secret key.
set -u
umask 077

script_dir=$(cd "$(dirname "$0")" && pwd)
template_dir=$script_dir/harmonia
harmonia_dir=/etc/harmonia
unit_dir=/etc/systemd/system
state_dir=/var/lib/nidrew
cache_url=http://127.0.0.1:5000
listen=127.0.0.1:5000
account=harmonia
reader=nidrew
profile=/nix/var/nix/profiles/nidrew-server
profile_bin=/nix/var/nix/profiles/default/bin
upstream_key=cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
restart=0
failures=0

usage() {
  cat <<'EOF'
Usage: sudo bash check-harmonia.sh [options]

  --restart             Restart harmonia.service before checking it
  --template-dir DIR    Templates (default: scripts/server/harmonia)
  --harmonia-dir DIR    Key and configuration directory (default: /etc/harmonia)
  --unit-dir DIR        systemd unit directory (default: /etc/systemd/system)
  --state-dir DIR       Recorded checksums (default: /var/lib/nidrew)

Exit status: 0 when ready, 1 when a check fails, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --template-dir | --harmonia-dir | --unit-dir | --state-dir)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      case $1 in
        --template-dir) template_dir=$2 ;;
        --harmonia-dir) harmonia_dir=$2 ;;
        --unit-dir) unit_dir=$2 ;;
        --state-dir) state_dir=$2 ;;
      esac
      shift 2
      ;;
    --restart)
      restart=1
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

report() { printf '[%s] %s: %s\n' "$1" "$2" "$3"; }
ok() { report ' ok ' "$1" "$2"; }
fail() {
  report 'FAIL' "$1" "$2"
  failures=$((failures + 1))
}
nix_cmd() { "$profile_bin/nix" --extra-experimental-features nix-command "$@"; }
as_reader() { runuser -u "$reader" -- "$@"; }

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run as root to inspect Harmonia: sudo bash %s\n' "$0" >&2
  exit 1
fi
cd / || exit 1
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
setup_hint="sudo bash $script_dir/setup-harmonia.sh"
secret=$harmonia_dir/secret-key
public=$harmonia_dir/public-key

# Account: a system account without sudo, extra groups, or Nix trust.
if id "$account" >/dev/null 2>&1; then
  uid=$(id -u "$account")
  shell=$(getent passwd "$account" | cut -d: -f7)
  uid_min=$(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null)
  [ "$uid" -lt "${uid_min:-1000}" ] && ok account "$account is a system account (uid $uid, shell $shell)" ||
    fail account "$account has uid $uid, not a system account"
  [ "$(id -nG "$account")" = "$account" ] && ok account "$account is only in group $account" ||
    fail account "$account is in groups $(id -nG "$account")"
  if sudo -l -U "$account" 2>/dev/null | grep -q 'may run the following'; then
    fail account "$account has sudo privileges"
  else
    ok account "$account has no sudo privileges"
  fi
  trusted=$(nix_cmd config show trusted-users 2>/dev/null)
  case " $trusted " in
    *" $account "* | *" @$account "*) fail account "$account is in trusted-users ($trusted)" ;;
    *) ok account "$account is not a Nix trusted user (trusted-users = $trusted)" ;;
  esac
  denied=
  for path in /nix/store /nix/var/nix/db /nix/var/nix/db/db.sqlite; do
    runuser -u "$account" -- test -w "$path" && denied="$denied $path"
  done
  [ -z "$denied" ] && ok store "$account cannot write /nix/store or the Nix database" ||
    fail store "$account can write:$denied"
  runuser -u "$account" -- test -r /nix/var/nix/db/db.sqlite &&
    ok store "$account can read the Nix database" || fail store "$account cannot read /nix/var/nix/db/db.sqlite"
else
  fail account "$account does not exist; run $setup_hint"
fi

# Signing key: root-only, valid, matching the published public key.
if [ -f "$secret" ] && [ ! -L "$secret" ]; then
  owner=$(stat -c %U:%G "$secret")
  mode=$(stat -c %a "$secret")
  [ "$owner" = root:root ] && [ "$mode" = 600 ] && ok key "$secret is $owner mode $mode" ||
    fail key "$secret is $owner mode $mode, expected root:root mode 600"
  if nix_cmd key convert-secret-to-public <"$secret" >"$work/public-key" 2>/dev/null; then
    cmp -s "$work/public-key" "$public" && ok key "$public matches the signing key: $(cat "$public")" ||
      fail key "$public is missing or does not match the signing key; run $setup_hint"
  else
    fail key "$secret is not a valid Nix signing key"
  fi
  for user in "$reader" "$account"; do
    if runuser -u "$user" -- head -c 0 "$secret" 2>/dev/null; then
      fail key "$user can read $secret"
    else
      ok key "$user cannot read $secret"
    fi
  done
  # Match the value from a private file, never from a command argument.
  cut -d: -f2- "$secret" >"$work/secret-value"
  leaked=
  for file in "$unit_dir/harmonia.service" "$unit_dir/harmonia.socket" "$harmonia_dir/harmonia.toml"; do
    ! grep -qFf "$work/secret-value" "$file" 2>/dev/null || leaked="$leaked $file"
  done
  journalctl -q -u harmonia.service -u harmonia.socket --no-pager 2>/dev/null |
    grep -qFf "$work/secret-value" && leaked="$leaked journal"
  rm -f "$work/secret-value"
  [ -z "$leaked" ] && ok key "the secret key is absent from the units, configuration, and journal" ||
    fail key "the secret key appears in:$leaked; rotate the key"
else
  fail key "$secret is missing or not a regular file; restore it from a backup or run $setup_hint"
fi

# Managed files.
for file in "$harmonia_dir/harmonia.toml" "$unit_dir/harmonia.service" "$unit_dir/harmonia.socket"; do
  cmp -s "$file" "$template_dir/${file##*/}" && ok files "$file matches the template" ||
    fail files "$file differs from $template_dir/${file##*/}; run $setup_hint"
done
if (sha256sum --quiet --check "$state_dir/managed.sha256" >/dev/null 2>&1); then
  ok files "managed files match the checksums in $state_dir/managed.sha256"
else
  fail files "managed files differ from $state_dir/managed.sha256 (local edits?); run $setup_hint"
fi

# Units and the local listener.
for unit in harmonia.socket harmonia.service; do
  [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = enabled ] && ok service "$unit is enabled" ||
    fail service "$unit is not enabled; run $setup_hint"
done
if [ $restart -eq 1 ]; then
  if systemctl restart harmonia.service; then
    ok service "restarted harmonia.service from $secret without other key input"
  else
    fail service "harmonia.service did not restart; see: journalctl -u harmonia.service"
  fi
fi
[ "$(systemctl is-active harmonia.socket)" = active ] && ok service "harmonia.socket is active" ||
  fail service "harmonia.socket is $(systemctl is-active harmonia.socket); after fixing the cause, run $setup_hint"
listeners=$(ss -Hltn | awk '$4 ~ /:5000$/ { print $4 }' | sort -u | paste -sd' ')
[ "$listeners" = "$listen" ] && ok service "only $listen listens on port 5000" ||
  fail service "port 5000 listeners are '${listeners:-none}', expected only $listen"
if [ "$(systemctl is-active harmonia.service)" = active ]; then
  pid=$(systemctl show -p MainPID --value harmonia.service)
  user=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
  [ "$user" = "$account" ] && ok service "harmonia.service is active as $user (pid $pid)" ||
    fail service "harmonia.service runs as '${user:-unknown}', expected $account"
else
  fail service "harmonia.service is $(systemctl is-active harmonia.service); see: journalctl -u harmonia.service; after fixing the cause, run $setup_hint"
fi

# Serving: a locally built path, so only Harmonia's signature can vouch for it.
# The socket accepts connections while the service waits to restart, so every
# request has a time limit.
path=$(readlink -f "$profile")
key=$(cat "$public" 2>/dev/null)
if info=$(curl -fsS --max-time 10 "$cache_url/nix-cache-info" 2>"$work/curl.err"); then
  ok cache "$cache_url/nix-cache-info: $(printf '%s' "$info" | tr '\n' ' ')"
  if [ -n "$key" ] && as_reader timeout 120 "$profile_bin/nix" --extra-experimental-features nix-command \
    store verify --store "$cache_url" --trusted-public-keys "$key" "$path" >"$work/verify.out" 2>&1; then
    ok cache "$reader verified $path from $cache_url with ${key%%:*}"
  else
    fail cache "$reader cannot verify $path from $cache_url with the public key: $(tr '\n' ' ' <"$work/verify.out")"
  fi
  as_reader timeout 120 "$profile_bin/nix" --extra-experimental-features nix-command store verify --no-contents \
    --store "$cache_url" --trusted-public-keys "$upstream_key" "$path" >"$work/verify.out" 2>&1
  if grep -q 'is untrusted' "$work/verify.out"; then
    ok cache "$path is rejected as untrusted without the Harmonia key"
  else
    fail cache "$path from $cache_url was not rejected as untrusted without the Harmonia key: $(tr '\n' ' ' <"$work/verify.out")"
  fi
else
  fail cache "$cache_url/nix-cache-info failed: $(cat "$work/curl.err")"
  report skip cache "signature checks need a responding cache"
fi

printf '\n'
if [ $failures -gt 0 ]; then
  printf 'Result: %s problem(s) found\n' "$failures"
  exit 1
fi
printf 'Result: Harmonia is ready on %s with %s\n' "$cache_url" "$key"
