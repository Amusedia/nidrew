#!/usr/bin/env bash
# Tests for check-prerequisites.sh using stub commands on a restricted PATH.
# Usage: scripts/server/tests/check-prerequisites-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
checker="$script_dir/../check-prerequisites.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

# Commands the checker may use, linked from the real system.
base_tools=(cat cut grep head id tr uname git)

# Build a bin directory with base tools, version stubs for download tools,
# and the given sudo and systemctl behavior. Arguments name tools to omit.
make_bin() {
  local bin=$1 sudo_mode=$2 systemctl_mode=$3
  shift 3
  local omit=" $* " tool
  rm -rf "$bin"
  mkdir -p "$bin"
  for tool in "${base_tools[@]}"; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  for tool in curl sha256sum tar xz; do
    case $omit in *" $tool "*) continue ;; esac
    printf '#!/bin/sh\necho "%s 1.0 (stub)"\n' "$tool" >"$bin/$tool"
    chmod +x "$bin/$tool"
  done
  case $sudo_mode in
    none) ;;
    ok) printf '#!/bin/sh\nexit 0\n' >"$bin/sudo" ;;
    password) printf '#!/bin/sh\necho "sudo: a password is required" >&2\nexit 1\n' >"$bin/sudo" ;;
    denied) printf '#!/bin/sh\necho "Sorry, user tester may not run sudo on host." >&2\nexit 1\n' >"$bin/sudo" ;;
    nnp) printf '#!/bin/sh\necho "sudo: The \\"no new privileges\\" flag is set, which prevents sudo from running as root." >&2\nexit 1\n' >"$bin/sudo" ;;
  esac
  case $systemctl_mode in
    running) printf '#!/bin/sh\ncase $1 in --version) echo "systemd 257 (stub)";; *) echo running;; esac\n' >"$bin/systemctl" ;;
    bus) printf '#!/bin/sh\ncase $1 in --version) echo "systemd 257 (stub)";; *) echo "Failed to connect to bus: Access denied" >&2; exit 1;; esac\n' >"$bin/systemctl" ;;
  esac
  chmod +x "$bin"/* 2>/dev/null || true
}

# Create a committed source repository.
make_repo() {
  local repo=$1
  git init -q "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid \
    commit -q --allow-empty -m "initial"
}

run_checker() {
  local bin=$1
  shift
  output=$(PATH="$bin" "$BASH" "$checker" "$@" 2>&1)
  status=$?
}

expect_status() {
  if [ "$status" -eq "$2" ]; then return 0; fi
  printf '  expected exit %s, got %s\n' "$2" "$status"
  return 1
}

expect_output() {
  if printf '%s\n' "$output" | grep -qF -- "$2"; then return 0; fi
  printf '  expected output containing: %s\n' "$2"
  return 1
}

expect_no_output() {
  if ! printf '%s\n' "$output" | grep -qF -- "$2"; then return 0; fi
  printf '  expected no output containing: %s\n' "$2"
  return 1
}

check() {
  local name=$1
  shift
  if "$@"; then
    passed=$((passed + 1))
    printf 'pass: %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\n%s\n' "$name" "$output"
  fi
}

pid1=$(cat /proc/1/comm 2>/dev/null || true)
repo="$work/source"
make_repo "$repo"
bin="$work/bin"

t_complete() {
  make_bin "$bin" ok running
  run_checker "$bin" --source "$repo"
  expect_status x 0 && expect_output x "[ ok ] curl:" &&
    expect_output x "[ ok ] source revision: HEAD ->" &&
    expect_output x "Result: required prerequisites are met"
}
if [ "$pid1" = systemd ]; then
  check "complete prerequisites succeed" t_complete
else
  printf 'skip: complete prerequisites succeed (PID 1 is %s, not systemd)\n' "$pid1"
fi

t_missing_tools() {
  make_bin "$bin" ok running curl xz
  run_checker "$bin" --source "$repo"
  expect_status x 1 && expect_output x "[FAIL] curl: not found" &&
    expect_output x "[FAIL] xz: not found" &&
    expect_output x "sudo apt-get install curl xz-utils"
}
check "missing download tools fail with install command" t_missing_tools

t_sudo_password() {
  make_bin "$bin" password running
  run_checker "$bin" --source "$repo"
  expect_output x "sudo requires a password"
}
check "sudo password requirement is reported" t_sudo_password

t_sudo_denied() {
  make_bin "$bin" denied running
  run_checker "$bin" --source "$repo"
  expect_output x "[warn] sudo: no sudo access for" &&
    expect_output x "Ask a Debian administrator"
}
check "missing sudo access is reported" t_sudo_denied

t_sudo_nnp() {
  make_bin "$bin" nnp running
  run_checker "$bin" --source "$repo"
  expect_output x "[warn] sudo: blocked by this session"
}
check "session sudo restriction is distinguished" t_sudo_nnp

t_sudo_missing() {
  make_bin "$bin" none running
  run_checker "$bin" --source "$repo"
  expect_output x "[warn] sudo: not installed"
}
check "missing sudo command is reported" t_sudo_missing

t_bus_denied() {
  make_bin "$bin" ok bus
  run_checker "$bin" --source "$repo"
  expect_output x "this session cannot reach the system bus"
}
if [ "$pid1" = systemd ]; then
  check "system bus restriction is distinguished" t_bus_denied
else
  printf 'skip: system bus restriction is distinguished (PID 1 is %s)\n' "$pid1"
fi

t_dirty_source() {
  make_bin "$bin" ok running
  printf 'edit\n' >"$repo/uncommitted.txt"
  run_checker "$bin" --source "$repo"
  rm -f "$repo/uncommitted.txt"
  expect_output x "[warn] source changes: 1 uncommitted" &&
    expect_output x "will not reach the server clone"
}
check "uncommitted source edits are reported" t_dirty_source

t_crlf_source() {
  make_bin "$bin" ok running
  printf 'line\n' >"$repo/text.txt"
  printf 'line\n' >"$repo/text-lf.txt"
  git -C "$repo" add text.txt text-lf.txt
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q -m text
  printf 'line\r\n' >"$repo/text.txt"
  # An LF file whose stat changed makes Git recheck it under core.autocrlf.
  touch -d '+1 hour' "$repo/text-lf.txt" 2>/dev/null || true
  run_checker "$bin" --source "$repo"
  git -C "$repo" checkout -q -- text.txt
  expect_output x "[ ok ] source changes: working tree clean" &&
    expect_no_output x "warning:"
}
check "Windows CRLF checkouts are not reported as edits" t_crlf_source

t_bad_revision() {
  make_bin "$bin" ok running
  run_checker "$bin" --source "$repo" --revision no-such-ref
  expect_status x 1 && expect_output x "[FAIL] source revision: no-such-ref"
}
check "unknown revision fails" t_bad_revision

t_missing_source() {
  make_bin "$bin" ok running
  run_checker "$bin" --source "$work/absent"
  expect_status x 1 && expect_output x "[FAIL] source repository: $work/absent not found"
}
check "missing source repository fails" t_missing_source

t_usage() {
  make_bin "$bin" ok running
  run_checker "$bin" --bogus
  expect_status x 2 && expect_output x "Usage:"
}
check "unknown argument is a usage error" t_usage

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
