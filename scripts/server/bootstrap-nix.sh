#!/usr/bin/env bash
# Install the pinned multi-user Nix with the upstream shell installer, after
# verifying the installer checksum, then run check-nix.sh. Run as root
# (through sudo). Rerunning with the pinned version installed only verifies;
# any other existing or partial installation is preserved and explained.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
release_file=$script_dir/nix-release.conf
nix_bin=/nix/var/nix/profiles/default/bin/nix
uninstall_guide=https://nix.dev/manual/nix/stable/installation/uninstall.html

usage() {
  cat <<'EOF'
Usage: sudo bash bootstrap-nix.sh [--release-file PATH]

Inspect existing Nix state. Without an installation, download the pinned
upstream installer, verify its SHA-256, and run it as
  install --daemon --yes --no-channel-add
Then verify the daemon, build users, and a build as nidrew with check-nix.sh.

  --release-file PATH   Pinned release (default: nix-release.conf beside this script)

Exit status: 0 when the pinned Nix is installed and verified, 1 when refused
or failed, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --release-file)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      release_file=$2
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

[ -r "$release_file" ] || refuse "cannot read release file $release_file"
version=$(sed -n 's/^NIX_VERSION=//p' "$release_file" | tail -n 1)
[ -n "$version" ] || refuse "NIX_VERSION is missing from release file $release_file"

run_check() {
  if [ "$(id -u)" -ne 0 ]; then
    printf 'Verify as an administrator with:\n  sudo bash %s --release-file %s\n' \
      "$script_dir/check-nix.sh" "$release_file"
    exit 0
  fi
  printf '\n'
  bash "$script_dir/check-nix.sh" --release-file "$release_file"
  exit $?
}

# Existing installation.
if [ -x "$nix_bin" ]; then
  installed=$("$nix_bin" --version 2>/dev/null | awk '{print $NF}')
  [ "$installed" = "$version" ] ||
    refuse "Nix ${installed:-of unknown version} is installed at $nix_bin, not the pinned $version; it is preserved" \
      "keep it by pinning $installed deliberately in $release_file, or uninstall it ($uninstall_guide) and rerun"
  [ -e /etc/systemd/system/nix-daemon.socket ] ||
    refuse "Nix $installed is installed but nix-daemon.socket is not set up; this is not a multi-user installation" \
      "uninstall it ($uninstall_guide) and rerun, or set up the daemon units from /nix/var/nix/profiles/default/lib/systemd/system"
  printf 'Nix %s multi-user installation found; nothing to install.\n' "$installed"
  run_check
fi

# Partial state from an earlier installation. The upstream installer cannot
# resume, so stop before changing anything.
leftovers=()
for path in /nix /etc/nix /etc/systemd/system/nix-daemon.service \
  /etc/systemd/system/nix-daemon.socket /etc/tmpfiles.d/nix-daemon.conf; do
  [ ! -e "$path" ] && [ ! -L "$path" ] || leftovers+=("$path")
done
for profile in /etc/bashrc /etc/profile.d/nix.sh /etc/zshrc /etc/bash.bashrc /etc/zsh/zshrc; do
  [ ! -e "$profile.backup-before-nix" ] || leftovers+=("$profile.backup-before-nix")
done
if [ ${#leftovers[@]} -gt 0 ]; then
  printf 'Found state from an earlier Nix installation without a working %s:\n' "$nix_bin" >&2
  printf '  %s\n' "${leftovers[@]}" >&2
  refuse "the upstream installer cannot resume a partial installation; nothing was changed" \
    "inspect these paths, remove them following $uninstall_guide (restore each *.backup-before-nix over its original), then rerun"
fi

printf 'No Nix installation found; Nix %s will be installed.\n' "$version"
if getent group nixbld >/dev/null; then
  printf 'Note: group nixbld exists (gid %s); the installer reuses it and matching nixbld users.\n' \
    "$(getent group nixbld | cut -d: -f3)"
fi

if [ "$(id -u)" -ne 0 ]; then
  printf 'Installing multi-user Nix must run as root. As an administrator, run:\n' >&2
  printf '  sudo bash %s --release-file %s\n' "$script_dir/bootstrap-nix.sh" "$release_file" >&2
  exit 1
fi

work=$(mktemp -d) || refuse "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT
bash "$script_dir/fetch-nix-installer.sh" --release-file "$release_file" --output "$work/install" ||
  refuse "the installer was not verified, so it was not run"

# Channels are not added: server packages come from the pinned flake lock.
printf 'Running the upstream installer: --daemon --yes --no-channel-add\n'
(cd "$work" && sh ./install --daemon --yes --no-channel-add) ||
  refuse "the upstream installer failed; see its output above" \
    "fix the reported problem; if it left partial state, this script lists it on the next run"
run_check
