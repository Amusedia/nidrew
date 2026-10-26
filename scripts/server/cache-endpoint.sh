#!/usr/bin/env bash
# Print the Harmonia cache endpoint and public key for deployment
# configuration: the current Debian IPv4 address, the port harmonia.socket
# listens on, and /etc/harmonia/public-key. Any user can run it; it changes
# nothing. The WSL NAT address can change when WSL restarts, so discover it
# again rather than recording it.
# Usage: bash cache-endpoint.sh [--public-key FILE]
set -u

public=/etc/harmonia/public-key

usage() {
  cat <<'EOF'
Usage: bash cache-endpoint.sh [--public-key FILE]

Print address=, port=, endpoint=, and public_key= lines for the Harmonia
cache.

  --public-key FILE     Public key (default: /etc/harmonia/public-key)

Exit status: 0 when printed, 1 when the endpoint is unavailable, 2 on usage
errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --public-key)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      public=$2
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

unavailable() {
  printf 'Cache endpoint unavailable: %s\n' "$1" >&2
  exit 1
}

listen=$(systemctl show -p Listen --value harmonia.socket 2>/dev/null | awk 'NR == 1 { print $1 }')
[ -n "$listen" ] ||
  unavailable "harmonia.socket has no listener; run setup-harmonia.sh as an administrator"
case $listen in
  '[::]:'*) port=${listen#'[::]:'} ;;
  *) unavailable "harmonia.socket listens on $listen only; run setup-harmonia.sh to expose the cache" ;;
esac
# The source address of the default route is the address the Windows host
# and WSL containers reach.
address=$(ip -4 route get 1.1.1.1 2>/dev/null |
  awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')
[ -n "$address" ] || unavailable "no IPv4 address on the default route"
key=$(cat "$public" 2>/dev/null) && [ -n "$key" ] || unavailable "cannot read $public"

printf 'address=%s\nport=%s\nendpoint=http://%s:%s\npublic_key=%s\n' \
  "$address" "$port" "$address" "$port" "$key"
