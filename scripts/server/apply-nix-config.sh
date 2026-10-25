#!/usr/bin/env bash
# Apply the Nidrew server-wide Nix settings and the locked server packages.
# Installs /etc/nix/nidrew.conf from nix/server/nidrew.conf, a system registry
# pinning nixpkgs to nix/server/flake.lock, and one include in nix.conf; then
# restarts the daemon when its configuration changed, builds the
# nidrew-server profile, and runs check-nix-config.sh. Run as root (through
# sudo). Matching files are left alone, unchanged managed files are updated,
# and local edits or unexpected files stop the run before anything changes.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
flake_dir=$script_dir/../../nix/server
conf_dir=/etc/nix
state_dir=/var/lib/nidrew
profile=/nix/var/nix/profiles/nidrew-server
files_only=0
include_line='include nidrew.conf'

usage() {
  cat <<'EOF'
Usage: sudo bash apply-nix-config.sh [options]

Install the Nidrew Nix settings and system nixpkgs registry, add
"include nidrew.conf" to nix.conf, restart nix-daemon when its configuration
changed, build the nidrew-server profile from the committed lock, and verify
with check-nix-config.sh. Never updates the lock.

  --flake-dir DIR      Server flake with flake.lock and nidrew.conf
                       (default: nix/server in this checkout)
  --nix-conf-dir DIR   Nix configuration directory (default: /etc/nix)
  --state-dir DIR      Checksums and previous files (default: /var/lib/nidrew)
  --profile PATH       Package profile (default: /nix/var/nix/profiles/nidrew-server)
  --files-only         Manage the configuration files only: no daemon restart,
                       profile build, or check (for tests)

Exit status: 0 when applied and verified, 1 when refused or failed, 2 on
usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --flake-dir | --nix-conf-dir | --state-dir | --profile)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      case $1 in
        --flake-dir) flake_dir=$2 ;;
        --nix-conf-dir) conf_dir=$2 ;;
        --state-dir) state_dir=$2 ;;
        --profile) profile=$2 ;;
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

refuse() {
  printf 'Refused: %s\n' "$1" >&2
  [ $# -lt 2 ] || printf 'Resolve: %s\n' "$2" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ] && { [ $files_only -eq 0 ] || [ "$conf_dir" = /etc/nix ]; }; then
  printf 'Applying the server Nix configuration must run as root. As an administrator, run:\n' >&2
  printf '  sudo bash %s\n' "$script_dir/apply-nix-config.sh" >&2
  exit 1
fi

nix_bin=/nix/var/nix/profiles/default/bin/nix
[ -x "$nix_bin" ] || nix_bin=$(command -v nix 2>/dev/null) ||
  refuse "Nix is not installed" "run bootstrap-nix.sh first"
nix_cmd() { "$nix_bin" --extra-experimental-features 'nix-command flakes' "$@"; }

flake_dir=$(cd "$flake_dir" 2>/dev/null && pwd) || refuse "cannot open the server flake directory"
template=$flake_dir/nidrew.conf
lock=$flake_dir/flake.lock
for file in "$flake_dir/flake.nix" "$lock" "$template"; do
  [ -r "$file" ] || refuse "cannot read $file"
done
nix_conf=$conf_dir/nix.conf
[ -f "$nix_conf" ] && [ ! -L "$nix_conf" ] ||
  refuse "$nix_conf is missing or not a regular file" "install Nix with bootstrap-nix.sh first"

work=$(mktemp -d) || refuse "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT

# The system registry entry is generated from the lock, so both change together.
NIDREW_LOCK=$lock nix_cmd eval --raw --impure --expr '
  let
    lock = builtins.fromJSON (builtins.readFile (builtins.getEnv "NIDREW_LOCK"));
    node = lock.nodes.${lock.nodes.${lock.root}.inputs.nixpkgs};
  in
  builtins.toJSON {
    version = 2;
    flakes = [ { from = { type = "indirect"; id = "nixpkgs"; }; to = node.locked; } ];
  }' >"$work/registry.json" 2>"$work/eval.err" ||
  refuse "cannot read the nixpkgs input from $lock: $(cat "$work/eval.err")"
printf '\n' >>"$work/registry.json"
rev=$(grep -o '"rev":"[0-9a-f]*"' "$work/registry.json" | cut -d'"' -f4)

# Plan every step before changing anything.
conflicts=0
conflict() {
  printf 'Conflict: %s\n  Resolve: %s\n' "$1" "$2" >&2
  conflicts=$((conflicts + 1))
}
recorded_sum() { awk -v p="$1" '$2 == p { s = $1 } END { print s }' "$state_dir/managed.sha256" 2>/dev/null; }

declare -A action
plan_file() {
  local target=$1 candidate=$2 source=$3 recorded
  recorded=$(recorded_sum "$target")
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    action[$target]=installed
  elif [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$target" "$candidate"; then
    action[$target]=unchanged
  elif [ -n "$recorded" ] && [ -f "$target" ] && [ ! -L "$target" ] &&
    [ "$(sha256sum "$target" | cut -c1-64)" = "$recorded" ]; then
    action[$target]=updated
  elif [ -n "$recorded" ]; then
    conflict "$target was edited locally since Nidrew last applied it; it is preserved" \
      "move the change into $source, or remove $target, then rerun"
  else
    conflict "$target exists and is not managed by Nidrew; it is preserved" \
      "compare it with $source; remove or rename it if Nidrew should own it, then rerun"
  fi
}
plan_file "$conf_dir/nidrew.conf" "$template" "$template"
plan_file "$conf_dir/registry.json" "$work/registry.json" "$lock"

keys=$(sed -n 's/^\([a-z-]*\)[[:space:]]*=.*/\1/p' "$template" | paste -sd'|')
while IFS= read -r line; do
  number=${line%%:*}
  key=$(printf '%s\n' "${line#*:}" | sed 's/^[[:space:]]*\([a-z-]*\).*/\1/')
  conflict "$nix_conf line $number sets $key, which Nidrew manages in nidrew.conf" \
    "remove the line from $nix_conf (or move a required value into $template), then rerun"
done < <(grep -nE "^[[:space:]]*(extra-)?($keys)[[:space:]]*=" "$nix_conf")
includes=$(grep -cxF "$include_line" "$nix_conf")
[ "$includes" -le 1 ] ||
  conflict "$nix_conf contains '$include_line' $includes times" "keep one copy, then rerun"

if [ $conflicts -gt 0 ]; then
  printf 'Refused: %s conflict(s); nothing was changed.\n' "$conflicts" >&2
  exit 1
fi

# Validate the complete candidate configuration before activation.
mkdir "$work/conf"
cp -a "$conf_dir/." "$work/conf/"
cp "$template" "$work/conf/nidrew.conf"
cp "$work/registry.json" "$work/conf/registry.json"
if [ "$includes" -eq 0 ]; then
  [ -z "$(tail -c 1 "$nix_conf")" ] || printf '\n' >>"$work/conf/nix.conf"
  printf '%s\n' "$include_line" >>"$work/conf/nix.conf"
fi
candidate_nix() {
  env -u NIX_CONFIG NIX_CONF_DIR="$work/conf" NIX_USER_CONF_FILES="$work/no-user-conf" \
    "$nix_bin" --extra-experimental-features nix-command "$@"
}
candidate_nix config show >/dev/null 2>"$work/validate.err" &&
  ! grep -qE '^(warning|error):' "$work/validate.err" ||
  refuse "the candidate configuration is invalid; nothing was changed: $(cat "$work/validate.err")"
while IFS= read -r line; do
  key=$(printf '%s' "${line%%=*}" | tr -d '[:space:]')
  value=$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  effective=$(candidate_nix config show "$key" 2>/dev/null)
  if [ "$key" = experimental-features ]; then
    for feature in $value; do
      case " $effective " in
        *" $feature "*) ;;
        *) refuse "candidate $key is '$effective', missing $feature; nothing was changed" ;;
      esac
    done
  elif [ "$effective" != "$value" ]; then
    refuse "candidate $key is '$effective', expected '$value'; another configuration file overrides it. Nothing was changed" \
      "find the setting in $conf_dir and remove it"
  fi
done < <(grep -E '^[a-z-]+[[:space:]]*=' "$template")
candidate_nix --extra-experimental-features flakes registry list 2>/dev/null |
  grep -qE "^system flake:nixpkgs .*$rev" ||
  refuse "the candidate system registry does not resolve nixpkgs to $rev; nothing was changed"

# Activate: managed files first, then the include that makes nix.conf use them.
mkdir -p "$state_dir/previous" || refuse "cannot create $state_dir"
record() {
  local target=$1
  { grep -v "  $target\$" "$state_dir/managed.sha256" 2>/dev/null; sha256sum "$target"; } \
    >"$state_dir/managed.sha256.new" && mv -f "$state_dir/managed.sha256.new" "$state_dir/managed.sha256"
}
replace() {
  local target=$1 source=$2
  cp "$source" "$target.nidrew-new" && chmod 0644 "$target.nidrew-new" &&
    mv -f "$target.nidrew-new" "$target" || refuse "cannot write $target"
}
config_changed=0
for target in "$conf_dir/nidrew.conf" "$conf_dir/registry.json"; do
  case ${action[$target]} in
    updated) cp -p "$target" "$state_dir/previous/${target##*/}" ;;
  esac
  [ "${action[$target]}" = unchanged ] || replace "$target" "$work/conf/${target##*/}"
  record "$target"
  printf '%s %s\n' "${action[$target]}" "$target"
  [ "${action[$target]}" = unchanged ] || [ "$target" = "$conf_dir/registry.json" ] || config_changed=1
done
if [ "$includes" -eq 0 ]; then
  cp -p "$nix_conf" "$state_dir/previous/nix.conf"
  replace "$nix_conf" "$work/conf/nix.conf"
  printf 'added "%s" to %s (previous copy in %s)\n' "$include_line" "$nix_conf" "$state_dir/previous"
  config_changed=1
else
  printf 'unchanged %s include\n' "$nix_conf"
fi
[ $files_only -eq 0 ] || exit 0

# The daemon reads its settings at startup; restart it if it predates them.
newest=$(stat -c %Y "$nix_conf" "$conf_dir/nidrew.conf" | sort -n | tail -n 1)
if [ "$(systemctl is-active nix-daemon.service)" = active ]; then
  started=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value nix-daemon.service)" +%s 2>/dev/null || echo 0)
  if [ $config_changed -eq 1 ] || [ "$started" -lt "$newest" ]; then
    systemctl restart nix-daemon.service || refuse "cannot restart nix-daemon.service"
    printf 'restarted nix-daemon.service\n'
  fi
fi

previous=
[ ! -e "$profile" ] || previous=$(readlink -f "$profile")
out=$(nix_cmd build --no-update-lock-file --no-write-lock-file --print-out-paths \
  --profile "$profile" "path:$flake_dir#default") ||
  refuse "building the server packages from $lock failed; see the output above" \
    "the lock is used as committed; if it is out of date, run update-server-lock.sh in the source checkout"
if [ "$previous" = "$out" ]; then
  printf 'unchanged %s -> %s\n' "$profile" "$out"
else
  printf 'built %s -> %s (previous: %s)\n' "$profile" "$out" "${previous:-none}"
fi

printf '\n'
bash "$script_dir/check-nix-config.sh" --flake-dir "$flake_dir" --nix-conf-dir "$conf_dir" \
  --state-dir "$state_dir" --profile "$profile"
