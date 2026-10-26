#!/usr/bin/env bash
# Report the Harmonia cache: the harmonia account and its store access, the
# signing key's protection, managed files, units, the listener and its port
# restrictions, access from loopback and rejection of other sources, and a
# locally built path that nidrew substitutes into a fresh store with the
# published public key and that is rejected without it. With --restart,
# restart harmonia.service first to show it recovers the key from protected
# Debian storage. Run as root (through sudo). Never prints the secret key.
set -u
umask 077

script_dir=$(cd "$(dirname "$0")" && pwd)
template_dir=$script_dir/harmonia
harmonia_dir=/etc/harmonia
unit_dir=/etc/systemd/system
state_dir=/var/lib/nidrew
port=5000
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
  --port PORT           Cache port (default: 5000)
  --template-dir DIR    Templates (default: scripts/server/harmonia)
  --harmonia-dir DIR    Key and configuration directory (default: /etc/harmonia)
  --unit-dir DIR        systemd unit directory (default: /etc/systemd/system)
  --state-dir DIR       Recorded checksums (default: /var/lib/nidrew)

Exit status: 0 when ready, 1 when a check fails, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --port | --template-dir | --harmonia-dir | --unit-dir | --state-dir)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      case $1 in
        --port) port=$2 ;;
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

case $port in
  '' | *[!0-9]* | 0*)
    printf 'Invalid port: %s\n' "$port" >&2
    usage >&2
    exit 2
    ;;
esac
cache_url=http://127.0.0.1:$port
table='inet nidrew_harmonia'
units="harmonia-firewall.service harmonia.socket harmonia.service"

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
[ "$port" = 5000 ] || setup_hint="$setup_hint --port $port"
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

# Managed files, compared with the templates for the selected port.
for file in "$harmonia_dir/harmonia.toml" "$harmonia_dir/firewall.sh" "$unit_dir/harmonia-firewall.service" \
  "$unit_dir/harmonia.socket" "$unit_dir/harmonia.service"; do
  if sed "s/@PORT@/$port/g" "$template_dir/${file##*/}" 2>/dev/null | cmp -s "$file" -; then
    ok files "$file matches the template for port $port"
  else
    fail files "$file differs from $template_dir/${file##*/} for port $port; run $setup_hint"
  fi
done
if (sha256sum --quiet --check "$state_dir/managed.sha256" >/dev/null 2>&1); then
  ok files "managed files match the checksums in $state_dir/managed.sha256"
else
  fail files "managed files differ from $state_dir/managed.sha256 (local edits?); run $setup_hint"
fi

# Units, the port restrictions, and the listener.
for unit in $units; do
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
for unit in harmonia-firewall.service harmonia.socket; do
  [ "$(systemctl is-active "$unit")" = active ] && ok service "$unit is active" ||
    fail service "$unit is $(systemctl is-active "$unit"); see: systemctl status $unit; after fixing the cause, run $setup_hint"
done
gateway=$(ip -4 route show default | awk '{ print $3; exit }')
rules=$("$profile/bin/nft" list table $table 2>/dev/null)
if [ -z "$rules" ]; then
  fail firewall "table $table is missing; restore it with: sudo systemctl restart harmonia-firewall.service harmonia.socket"
else
  printf '%s\n' "$rules" | grep -qF "tcp dport $port ip saddr { 127.0.0.0/8, $gateway } accept" &&
    ok firewall "port $port accepts IPv4 from loopback and the WSL NAT gateway $gateway only" ||
    fail firewall "table $table does not allow exactly loopback and the current gateway ${gateway:-none}; restart harmonia-firewall.service"
  printf '%s\n' "$rules" | grep -qF "tcp dport $port ip6 saddr ::1 accept" &&
    ok firewall "port $port accepts IPv6 from ::1 only" || fail firewall "table $table lacks the IPv6 loopback rule"
  printf '%s\n' "$rules" | grep -qE "tcp dport $port counter packets [0-9]+ bytes [0-9]+ drop" &&
    ok firewall "port $port drops every other IPv4 and IPv6 source" || fail firewall "table $table lacks the drop rule"
fi
listeners=$(ss -Hltn | awk -v p=":$port" 'substr($4, length($4) - length(p) + 1) == p { print $4 }' | sort -u | paste -sd' ')
case $listeners in
  "*:$port" | "[::]:$port") ok service "harmonia.socket listens on all IPv4 and IPv6 addresses at port $port" ;;
  *) fail service "port $port listeners are '${listeners:-none}', expected only [::]:$port" ;;
esac
if [ "$(systemctl is-active harmonia.service)" = active ]; then
  pid=$(systemctl show -p MainPID --value harmonia.service)
  user=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
  [ "$user" = "$account" ] && ok service "harmonia.service is active as $user (pid $pid)" ||
    fail service "harmonia.service runs as '${user:-unknown}', expected $account"
else
  fail service "harmonia.service is $(systemctl is-active harmonia.service); see: journalctl -u harmonia.service; after fixing the cause, run $setup_hint"
fi

# Access: loopback is served; a source outside the allowed set, here this
# instance's own eth0 and link-local addresses, is dropped. The socket accepts
# connections while the service waits to restart, so every request has a time
# limit.
responding=0
for url in "$cache_url" "http://[::1]:$port"; do
  if info=$(curl -fsS -g --max-time 10 "$url/nix-cache-info" 2>"$work/curl.err"); then
    ok access "$url/nix-cache-info: $(printf '%s' "$info" | tr '\n' ' ')"
    responding=1
  else
    fail access "$url/nix-cache-info failed: $(cat "$work/curl.err")"
  fi
done
drops() { "$profile/bin/nft" list table $table 2>/dev/null | awk '/ drop$/ { for (i = 1; i < NF; i++) if ($i == "packets") print $(i + 1) }'; }
self=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')
link_local=$(ip -6 -o addr show dev eth0 scope link 2>/dev/null | awk '{ sub("/.*", "", $4); print $4; exit }')
[ -n "$self" ] || fail access "no IPv4 address on the default route to test rejection from"
for source in $self $link_local; do
  # A link-local destination already uses the link-local source; binding to
  # a link-local address would need a scope.
  case $source in
    *:*) url="http://[$source%25eth0]:$port/nix-cache-info" bind= ;;
    *) url="http://$source:$port/nix-cache-info" bind=$source ;;
  esac
  before=$(drops)
  if curl -sS -g --max-time 3 ${bind:+--interface "$bind"} "$url" >/dev/null 2>&1; then
    fail access "$url was served to $source; the port restriction is not effective"
  elif [ "$(drops)" -gt "${before:-0}" ] 2>/dev/null; then
    ok access "a connection from $source, outside the allowed sources, was dropped"
  else
    fail access "a connection from $source failed without reaching the drop rule"
  fi
done

# Substitution into a fresh store: a path built locally as nidrew, so only
# Harmonia's signature can vouch for it, with signatures required.
key=$(cat "$public" 2>/dev/null)
copy() {
  local store status
  store=$(as_reader mktemp -d) || return 1
  as_reader timeout 120 "$profile_bin/nix" --extra-experimental-features nix-command copy \
    --option require-sigs true --trusted-public-keys "$1" --from "$cache_url" --to "$store/store" "$path" \
    >"$work/copy.out" 2>&1
  status=$?
  as_reader chmod -R u+w "$store" 2>/dev/null
  rm -rf "$store"
  return $status
}
if [ $responding -eq 1 ] && [ -n "$key" ]; then
  expr=$(printf 'derivation { name = "nidrew-cache-check"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ok > $out" ]; nonce = "%s"; }' "$(date +%s%N)")
  if path=$(as_reader timeout 120 "$profile_bin/nix-build" --no-out-link --quiet -E "$expr" 2>"$work/build.err"); then
    if copy "$key"; then
      ok cache "$reader substituted $path from $cache_url into a fresh store with ${key%%:*}"
    else
      fail cache "$reader cannot substitute $path from $cache_url with the public key: $(tr '\n' ' ' <"$work/copy.out")"
    fi
    if ! copy "$upstream_key" && grep -q 'lacks a signature by a trusted key' "$work/copy.out"; then
      ok cache "a fresh store without the Harmonia key rejects $path"
    else
      fail cache "a fresh store without the Harmonia key did not reject $path: $(tr '\n' ' ' <"$work/copy.out")"
    fi
  else
    fail cache "$reader cannot build a test path: $(tr '\n' ' ' <"$work/build.err")"
  fi
else
  report skip cache "substitution checks need a responding cache and $public"
fi

printf '\n'
if [ $failures -gt 0 ]; then
  printf 'Result: %s problem(s) found\n' "$failures"
  exit 1
fi
printf 'Result: Harmonia is ready on port %s with %s\n' "$port" "$key"
