#!/bin/sh
# Installed as /etc/harmonia/firewall.sh by scripts/server/setup-harmonia.sh
# and run by harmonia-firewall.service before harmonia.socket listens. Allows
# the cache port only from loopback and the WSL NAT gateway, which carries the
# Windows host's and WSL containers' connections, and drops it from every
# other IPv4 and IPv6 source. Manages only the nidrew_harmonia table.
set -u
table='inet nidrew_harmonia'

usage() {
  printf 'Usage: firewall.sh start PORT | stop\n' >&2
  exit 2
}

case ${1:-} in
  stop)
    nft delete table $table 2>/dev/null
    printf 'removed table %s\n' "$table"
    exit 0
    ;;
  start) [ $# -eq 2 ] || usage ;;
  *) usage ;;
esac
port=$2
case $port in
  '' | *[!0-9]* | 0*) usage ;;
esac
[ "$port" -le 65535 ] || usage

mode=$(wslinfo --networking-mode 2>/dev/null)
if [ "$mode" != nat ]; then
  printf "WSL networking mode is '%s'; the cache restrictions support only nat\n" "$mode" >&2
  exit 1
fi

# WSL configures eth0 around the time systemd starts.
tries=0
while gateway=$(ip -4 route show default | awk '{ print $3; exit }'); [ -z "$gateway" ]; do
  tries=$((tries + 1))
  if [ $tries -gt 30 ]; then
    printf 'no IPv4 default route after 30 s; cannot identify the WSL NAT gateway\n' >&2
    exit 1
  fi
  sleep 1
done

# Declaring the table first lets the delete succeed on the first start; the
# whole file is applied as one transaction.
nft -f - <<EOF || exit 1
table $table
delete table $table
table $table {
  chain input {
    type filter hook input priority filter; policy accept;
    tcp dport $port ip saddr { 127.0.0.0/8, $gateway } accept
    tcp dport $port ip6 saddr ::1 accept
    tcp dport $port counter drop
  }
}
EOF
printf 'cache port %s allowed from loopback and %s only\n' "$port" "$gateway"
