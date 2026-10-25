#!/usr/bin/env bash
# Download the pinned upstream Nix installer and verify its SHA-256 checksum.
# The installer itself checks the binary tarball against the hash it embeds.
# Never runs the installer and needs no root; a mismatch keeps no file.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
release_file=$script_dir/nix-release.conf
output=

usage() {
  cat <<'EOF'
Usage: fetch-nix-installer.sh --output PATH [--release-file PATH]

Download NIX_INSTALLER_URL from the release file and write it to PATH only if
its SHA-256 matches NIX_INSTALLER_SHA256.

  --output PATH         Where to write the verified installer
  --release-file PATH   Pinned release (default: nix-release.conf beside this script)

Exit status: 0 when verified, 1 when refused or failed, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --output | --release-file)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      if [ "$1" = --output ]; then output=$2; else release_file=$2; fi
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
if [ -z "$output" ]; then
  usage >&2
  exit 2
fi

refuse() {
  printf 'Refused: %s\n' "$1" >&2
  exit 1
}

[ -r "$release_file" ] || refuse "cannot read release file $release_file"
release_value() { sed -n "s/^$1=//p" "$release_file" | tail -n 1; }
version=$(release_value NIX_VERSION)
url=$(release_value NIX_INSTALLER_URL)
expected=$(release_value NIX_INSTALLER_SHA256)

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || refuse "NIX_VERSION '$version' in $release_file is not a release version"
# file:// serves local copies, as in the tests; plain http is never accepted.
[[ $url =~ ^(https|file):// ]] || refuse "NIX_INSTALLER_URL '$url' in $release_file must use https"
[[ $expected =~ ^[0-9a-f]{64}$ ]] || refuse "NIX_INSTALLER_SHA256 in $release_file is not a SHA-256 hex digest"

tmp=$(mktemp "$output.XXXXXX") || refuse "cannot create a file next to $output"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --proto '=https,file' -o "$tmp" "$url" || refuse "download failed for $url"
actual=$(sha256sum "$tmp" | cut -c1-64)
[ "$actual" = "$expected" ] ||
  refuse "checksum mismatch for $url; expected $expected, got $actual. The installer was not kept or run."

chmod 0644 "$tmp" && mv "$tmp" "$output" || refuse "cannot write $output"
trap - EXIT
printf 'Verified Nix %s installer: sha256 %s\n' "$version" "$actual"
