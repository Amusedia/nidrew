#!/usr/bin/env bash
# Tests for fetch-nix-installer.sh using local file:// installers.
# Usage: scripts/server/tests/fetch-nix-installer-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
fetch="$(cd "$script_dir/.." && pwd)/fetch-nix-installer.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
output=
status=0

installer="$work/install"
marker="$work/installer-ran"
release="$work/nix-release.conf"
out="$work/out/install"

reset() {
  rm -rf "$work/out" "$marker"
  mkdir -p "$work/out"
  printf '#!/bin/sh\ntouch %s\n' "$marker" >"$installer"
  write_release "$(sha256sum "$installer" | cut -c1-64)" "file://$installer"
}

write_release() {
  cat >"$release" <<EOF
# test release
NIX_VERSION=9.9.9
NIX_INSTALLER_URL=$2
NIX_INSTALLER_SHA256=$1
EOF
}

run_fetch() {
  output=$(bash "$fetch" --release-file "$release" "$@" 2>&1)
  status=$?
}

expect_status() {
  if [ "$status" -eq "$1" ]; then return 0; fi
  printf '  expected exit %s, got %s\n' "$1" "$status"
  return 1
}

expect_output() {
  if printf '%s\n' "$output" | grep -qF -- "$1"; then return 0; fi
  printf '  expected output containing: %s\n' "$1"
  return 1
}

expect_no_output_file() {
  if [ -z "$(ls -A "$work/out")" ]; then return 0; fi
  printf '  expected no files in output directory, found: %s\n' "$(ls -A "$work/out")"
  return 1
}

check() {
  local name=$1
  shift
  reset
  if "$@"; then
    passed=$((passed + 1))
    printf 'pass: %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\n%s\n' "$name" "$output"
  fi
}

t_matching_checksum() {
  run_fetch --output "$out"
  expect_status 0 && expect_output "Verified Nix 9.9.9 installer" &&
    cmp -s "$installer" "$out" && [ ! -e "$marker" ]
}

t_mismatch_rejected() {
  write_release "$(printf '0%.0s' $(seq 64))" "file://$installer"
  run_fetch --output "$out"
  expect_status 1 && expect_output "checksum mismatch" &&
    expect_output "expected 0000" &&
    expect_output "got $(sha256sum "$installer" | cut -c1-64)" &&
    expect_no_output_file && [ ! -e "$marker" ]
}

t_modified_installer_rejected() {
  printf 'echo tampered\n' >>"$installer"
  run_fetch --output "$out"
  expect_status 1 && expect_output "checksum mismatch" && expect_no_output_file
}

t_download_failure() {
  write_release "$(sha256sum "$installer" | cut -c1-64)" "file://$work/missing"
  run_fetch --output "$out"
  expect_status 1 && expect_output "download failed" && expect_no_output_file
}

t_invalid_checksum_value() {
  write_release "not-a-checksum" "file://$installer"
  run_fetch --output "$out"
  expect_status 1 && expect_output "NIX_INSTALLER_SHA256" && expect_no_output_file
}

t_disallowed_scheme() {
  write_release "$(sha256sum "$installer" | cut -c1-64)" "http://example.invalid/install"
  run_fetch --output "$out"
  expect_status 1 && expect_output "NIX_INSTALLER_URL" && expect_no_output_file
}

t_missing_output_is_usage_error() {
  run_fetch
  expect_status 2 && expect_output "Usage:"
}

check "matching checksum writes the installer without running it" t_matching_checksum
check "checksum mismatch is rejected and nothing is kept" t_mismatch_rejected
check "a modified installer is rejected" t_modified_installer_rejected
check "download failure is reported" t_download_failure
check "malformed pinned checksum is rejected" t_invalid_checksum_value
check "non-https download URL is rejected" t_disallowed_scheme
check "missing --output is a usage error" t_missing_output_is_usage_error

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
