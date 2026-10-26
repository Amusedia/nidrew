#!/usr/bin/env bash
# Report the Nidrew server Nix configuration: managed files, effective settings
# for nidrew, daemon restart, system registry and <nixpkgs> against
# nix/server/flake.lock, no channels, the nidrew-server profile, and Skopeo
# inspecting and copying a small digest-pinned image as nidrew into a temporary
# directory. Runs check-nix.sh first for the daemon and a sandboxed build.
# Run as root (through sudo). Needs network access for the Skopeo check.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
flake_dir=$script_dir/../../nix/server
conf_dir=/etc/nix
state_dir=/var/lib/nidrew
profile=/nix/var/nix/profiles/nidrew-server
account=nidrew
profile_bin=/nix/var/nix/profiles/default/bin
# busybox 1.37.0 multi-architecture index, pinned by digest.
skopeo_image=docker://docker.io/library/busybox@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
failures=0

usage() {
  cat <<'EOF'
Usage: sudo bash check-nix-config.sh [options]

  --flake-dir DIR      Server flake (default: nix/server in this checkout)
  --nix-conf-dir DIR   Nix configuration directory (default: /etc/nix)
  --state-dir DIR      Recorded checksums (default: /var/lib/nidrew)
  --profile PATH       Package profile (default: /nix/var/nix/profiles/nidrew-server)
  --skopeo-image REF   Digest-pinned image to inspect and copy (default: busybox 1.37.0)

Exit status: 0 when ready, 1 when a check fails, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --flake-dir | --nix-conf-dir | --state-dir | --profile | --skopeo-image)
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
        --skopeo-image) skopeo_image=$2 ;;
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

report() { printf '[%s] %s: %s\n' "$1" "$2" "$3"; }
ok() { report ' ok ' "$1" "$2"; }
fail() {
  report 'FAIL' "$1" "$2"
  failures=$((failures + 1))
}
nix_cmd() { "$profile_bin/nix" --extra-experimental-features 'nix-command flakes' "$@"; }
# A login shell, so environment overrides such as NIX_PATH are included.
as_account() { runuser -l "$account" -c "$1"; }
json_field() {
  NIDREW_JSON=$1 nix_cmd eval --raw --impure --expr \
    "(builtins.fromJSON (builtins.readFile (builtins.getEnv \"NIDREW_JSON\")))$2" 2>/dev/null
}

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run as root to inspect the Nix configuration: sudo bash %s\n' "$0" >&2
  exit 1
fi
cd / || exit 1
flake_dir=$(cd "$flake_dir" 2>/dev/null && pwd) || {
  printf 'Cannot open the server flake directory\n' >&2
  exit 1
}
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

bash "$script_dir/check-nix.sh" || failures=$((failures + 1))
printf '\n'

# Managed files.
lock_rev=$(json_field "$flake_dir/flake.lock" '.nodes.nixpkgs.locked.rev')
lock_hash=$(json_field "$flake_dir/flake.lock" '.nodes.nixpkgs.locked.narHash')
apply_hint="sudo bash $script_dir/apply-nix-config.sh"
if cmp -s "$conf_dir/nidrew.conf" "$flake_dir/nidrew.conf"; then
  ok files "$conf_dir/nidrew.conf matches $flake_dir/nidrew.conf"
else
  fail files "$conf_dir/nidrew.conf differs from $flake_dir/nidrew.conf; run $apply_hint"
fi
if grep -q "\"rev\":\"$lock_rev\"" "$conf_dir/registry.json" 2>/dev/null &&
  grep -qF "\"narHash\":\"$lock_hash\"" "$conf_dir/registry.json"; then
  ok files "$conf_dir/registry.json pins nixpkgs $lock_rev"
else
  fail files "$conf_dir/registry.json does not pin nixpkgs $lock_rev; run $apply_hint"
fi
includes=$(grep -cxF 'include nidrew.conf' "$conf_dir/nix.conf")
[ "$includes" -eq 1 ] && ok files "$conf_dir/nix.conf includes nidrew.conf once" ||
  fail files "$conf_dir/nix.conf includes nidrew.conf $includes times; run $apply_hint"
if (cd / && sha256sum --quiet --check "$state_dir/managed.sha256" >/dev/null 2>&1); then
  ok files "managed files match the checksums in $state_dir/managed.sha256"
else
  fail files "managed files differ from $state_dir/managed.sha256 (local edits?); run $apply_hint"
fi

# Effective settings as nidrew, including any user configuration.
while IFS= read -r line; do
  key=$(printf '%s' "${line%%=*}" | tr -d '[:space:]')
  value=$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  effective=$(as_account "$profile_bin/nix config show $key" 2>/dev/null)
  matched=1
  if [ "$key" = experimental-features ]; then
    for feature in $value; do
      case " $effective " in *" $feature "*) ;; *) matched=0 ;; esac
    done
  else
    [ "$effective" = "$value" ] || matched=0
  fi
  [ $matched -eq 1 ] && ok settings "$key = $effective" ||
    fail settings "$key is '$effective' for $account, expected '$value'"
done < <(grep -E '^[a-z-]+[[:space:]]*=' "$flake_dir/nidrew.conf")

# The daemon reads settings at startup.
if [ "$(systemctl is-active nix-daemon.service)" = active ]; then
  started=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value nix-daemon.service)" +%s 2>/dev/null || echo 0)
  newest=$(stat -c %Y "$conf_dir/nix.conf" "$conf_dir/nidrew.conf" 2>/dev/null | sort -n | tail -n 1)
  [ "$started" -ge "${newest:-0}" ] && ok daemon "nix-daemon.service started after the last configuration change" ||
    fail daemon "nix-daemon.service predates its configuration; run: sudo systemctl restart nix-daemon.service"
else
  ok daemon "nix-daemon.service is not running; socket activation starts it with the current configuration"
fi

# Registry and <nixpkgs> resolve to the locked revision for nidrew.
as_account "$profile_bin/nix flake metadata --json nixpkgs" >"$work/metadata.json" 2>"$work/metadata.err"
resolved_rev=$(json_field "$work/metadata.json" '.locked.rev')
resolved_hash=$(json_field "$work/metadata.json" '.locked.narHash')
resolved_path=$(json_field "$work/metadata.json" '.path')
if [ -n "$lock_rev" ] && [ "$resolved_rev" = "$lock_rev" ] && [ "$resolved_hash" = "$lock_hash" ]; then
  ok registry "flake:nixpkgs resolves to the locked $lock_rev"
else
  fail registry "flake:nixpkgs resolves to '${resolved_rev:-nothing}', lock has $lock_rev: $(tr '\n' ' ' <"$work/metadata.err")"
fi
nixpkgs_path=$(as_account "$profile_bin/nix-instantiate --find-file nixpkgs" 2>/dev/null)
if [ -n "$resolved_path" ] && [ "$nixpkgs_path" = "$resolved_path" ]; then
  version=$(as_account "$profile_bin/nix-instantiate --eval --expr '(import <nixpkgs> {}).lib.version'" 2>/dev/null)
  ok nixpkgs "<nixpkgs> is $nixpkgs_path (lib.version $version)"
else
  fail nixpkgs "<nixpkgs> is '${nixpkgs_path:-not found}', expected $resolved_path"
fi
channels=$( { "$profile_bin/nix-channel" --list; as_account "$profile_bin/nix-channel --list"; } 2>/dev/null)
if [ -z "$channels" ] && [ ! -e /nix/var/nix/profiles/per-user/root/channels ] &&
  [ ! -e "/home/$account/.nix-defexpr/channels" ]; then
  ok channels "no channels for root or $account"
else
  fail channels "channels found: $(printf '%s' "$channels" | tr '\n' ' '); remove them with nix-channel --remove"
fi

# Server packages.
expected=$(nix_cmd eval --raw --no-update-lock-file "path:$flake_dir#default.outPath" 2>/dev/null)
current=$(readlink -f "$profile" 2>/dev/null)
if [ -n "$expected" ] && [ "$current" = "$expected" ]; then
  ok packages "$profile -> $current"
else
  fail packages "$profile is '${current:-missing}', the lock gives '${expected:-nothing}'; run $apply_hint"
fi
# Harmonia 3 serves the cache with harmonia-cache; its harmonia binary is a
# Nix-compatible CLI, so report package names rather than --version output.
for tool in harmonia-cache skopeo nft; do
  if [ -x "$profile/bin/$tool" ]; then
    package=$(readlink -f "$profile/bin/$tool")
    package=${package#/nix/store/*-}
    ok packages "$tool from ${package%%/*}"
  else
    fail packages "$profile/bin/$tool is missing"
  fi
done

# Skopeo as nidrew: the digest pins the content, so no signature policy is
# needed for this test image; the destination is a private temporary directory.
if [ -x "$profile/bin/skopeo" ]; then
  dest=$(runuser -u "$account" -- mktemp -d)
  printf '{"default":[{"type":"insecureAcceptAnything"}]}\n' >"$work/policy.json"
  chmod 0644 "$work/policy.json"
  chmod 0755 "$work"
  skopeo="$profile/bin/skopeo --policy $work/policy.json"
  if arch=$(as_account "$skopeo inspect --format '{{.Architecture}}' $skopeo_image" 2>"$work/skopeo.err"); then
    ok skopeo "$account inspected $skopeo_image ($arch)"
  else
    fail skopeo "$account cannot inspect $skopeo_image: $(tr '\n' ' ' <"$work/skopeo.err")"
  fi
  if as_account "$skopeo copy --quiet $skopeo_image oci:$dest/oci:test" >/dev/null 2>"$work/skopeo.err" &&
    copied=$(as_account "$skopeo inspect --format '{{.Digest}}' oci:$dest/oci:test" 2>>"$work/skopeo.err"); then
    ok skopeo "$account copied it to oci:$dest/oci:test ($copied)"
  else
    fail skopeo "$account cannot copy $skopeo_image: $(tr '\n' ' ' <"$work/skopeo.err")"
  fi
  rm -rf "$dest"
fi

printf '\n'
if [ $failures -gt 0 ]; then
  printf 'Result: %s problem(s) found\n' "$failures"
  exit 1
fi
printf 'Result: server Nix configuration is ready (nixpkgs %s)\n' "$lock_rev"
