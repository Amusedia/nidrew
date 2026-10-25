#!/usr/bin/env bash
# Report whether this Linux instance meets Nidrew server setup prerequisites.
# Changes nothing. Run as the administrative account from a normal Debian shell.
set -u

source_path=/mnt/c/projects/nidrew
revision=HEAD

usage() {
  cat <<'EOF'
Usage: check-prerequisites.sh [--source PATH] [--revision REV]

Report Debian, WSL, Bash, systemd, Git, download/verification tools, sudo
access, and the source repository revision that server setup will clone.

  --source PATH    Source Git repository (default: /mnt/c/projects/nidrew)
  --revision REV   Committed revision to select (default: HEAD)

Exit status: 0 when required prerequisites are met, 1 when any are missing,
2 on usage errors. Warnings and manual actions do not change the status.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --source | --revision)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      if [ "$1" = --source ]; then source_path=$2; else revision=$2; fi
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

failures=0
actions=()
missing_packages=()

report() { printf '[%s] %s: %s\n' "$1" "$2" "$3"; }
ok() { report ' ok ' "$1" "$2"; }
warn() { report 'warn' "$1" "$2"; }
fail() {
  report 'FAIL' "$1" "$2"
  failures=$((failures + 1))
}
skip() { report 'skip' "$1" "$2"; }
first_line() { "$@" 2>&1 | head -n 1; }

user=$(id -un)

# Session restrictions: an agent sandbox may block privilege changes.
if grep -q '^NoNewPrivs:[[:space:]]*1' /proc/self/status 2>/dev/null; then
  warn session "no_new_privs is set; sudo and some host checks reflect this session, not the host"
fi

# Distribution.
if [ -r /etc/os-release ]; then
  os_id=$(grep -m1 '^ID=' /etc/os-release | cut -d= -f2- | tr -d '"')
  os_name=$(grep -m1 '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
  if [ "$os_id" = debian ]; then
    ok distribution "$os_name"
  else
    warn distribution "$os_name; only Debian is tested"
  fi
else
  warn distribution "/etc/os-release not readable; only Debian is tested"
fi

kernel=$(uname -r)
case $kernel in
  *microsoft* | *WSL*) ok wsl "kernel $kernel" ;;
  *) warn wsl "kernel $kernel does not look like WSL; Windows host steps do not apply" ;;
esac

if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
  ok bash "$BASH_VERSION"
else
  fail bash "$BASH_VERSION; Bash 4 or later is required"
fi

# systemd must be PID 1 for the Nix daemon and Harmonia services.
pid1=$(cat /proc/1/comm 2>/dev/null || echo unknown)
if [ "$pid1" != systemd ]; then
  fail systemd "PID 1 is $pid1, not systemd"
  actions+=("Enable systemd: add '[boot]' and 'systemd=true' to /etc/wsl.conf (sudo), then run 'wsl.exe --shutdown' from Windows and reopen Debian.")
elif ! command -v systemctl >/dev/null; then
  fail systemd "PID 1 is systemd but systemctl was not found"
else
  systemd_version=$(first_line systemctl --version)
  state=$(systemctl is-system-running 2>&1)
  case $state in
    running) ok systemd "$systemd_version; system $state" ;;
    degraded)
      warn systemd "$systemd_version; system degraded"
      actions+=("Inspect failed units with 'systemctl --failed'; unrelated failures may be acceptable.")
      ;;
    *"Failed to connect to bus"* | *"Access denied"* | *"Permission denied"*)
      warn systemd "PID 1 is systemd, but this session cannot reach the system bus ($state)"
      actions+=("Rerun this check from a normal Debian shell (for example 'wsl.exe --distribution Debian') to inspect services.")
      ;;
    *) warn systemd "$systemd_version; system state: $state" ;;
  esac
fi

# Git and the tools used to download and verify the Nix installer.
check_tool() {
  local tool=$1 package=$2
  if command -v "$tool" >/dev/null; then
    ok "$tool" "$(first_line "$tool" --version)"
  else
    fail "$tool" "not found"
    missing_packages+=("$package")
  fi
}
check_tool git git
check_tool curl curl
check_tool sha256sum coreutils
check_tool tar tar
check_tool xz xz-utils
if [ ${#missing_packages[@]} -gt 0 ]; then
  actions+=("Install missing tools as an administrator: sudo apt-get install ${missing_packages[*]}")
fi

# Administrative access. Setup prints privileged commands for an administrator.
if ! command -v sudo >/dev/null; then
  warn sudo "not installed; run administrative steps as root or install sudo"
else
  sudo_output=$(sudo -n true 2>&1)
  sudo_status=$?
  if [ $sudo_status -eq 0 ]; then
    ok sudo "available to $user without a password prompt"
  else
    case $sudo_output in
      *"no new privileges"*)
        warn sudo "blocked by this session (no_new_privs); not evidence about $user's host access"
        actions+=("Run administrative steps from a normal Debian shell, not from the restricted session.")
        ;;
      *"password is required"*)
        if id -nG | grep -qw sudo; then
          ok sudo "$user is in group sudo; sudo requires a password, so run printed admin commands interactively"
        else
          warn sudo "sudo requires a password; $user is not in group sudo, so access is unverified"
        fi
        ;;
      *"may not run sudo"* | *"not in the sudoers"* | *"not allowed"*)
        warn sudo "no sudo access for $user"
        actions+=("Ask a Debian administrator to run the administrative setup steps, or grant $user sudo access.")
        ;;
      *)
        warn sudo "could not determine access: $sudo_output"
        ;;
    esac
  fi
fi

# Source repository and committed revision for the server clone.
if [ ! -d "$source_path" ]; then
  fail "source repository" "$source_path not found"
  actions+=("Pass --source with the path of the Nidrew Git repository as seen from Linux.")
elif ! command -v git >/dev/null; then
  skip "source repository" "git is not available"
else
  top=$(git -C "$source_path" rev-parse --show-toplevel 2>&1)
  if [ $? -ne 0 ]; then
    case $top in
      *"dubious ownership"*)
        fail "source repository" "$source_path is owned by another user; Git refuses it"
        actions+=("If you trust it, run as $user: git config --global --add safe.directory $source_path")
        ;;
      *) fail "source repository" "$source_path is not a Git repository: $top" ;;
    esac
  else
    ok "source repository" "$top"
    commit=$(git -C "$source_path" rev-parse --verify --quiet "$revision^{commit}")
    if [ -z "$commit" ]; then
      fail "source revision" "$revision does not name a commit in $top"
    else
      subject=$(git -C "$source_path" log -1 --format=%s "$commit")
      ok "source revision" "$revision -> $commit ($subject)"
      # A Windows checkout with core.autocrlf has CRLF files that Linux Git
      # would report as modified; the clone receives committed content only.
      # Use diff rather than status, which treats a size change as modified.
      # Suppress line-ending conversion warnings for LF working files.
      changes=$({
        git -C "$source_path" -c core.autocrlf=true -c core.safecrlf=false diff --name-only HEAD
        git -C "$source_path" ls-files --others --exclude-standard
      } | grep -c .)
      if [ "$changes" -gt 0 ]; then
        warn "source changes" "$changes uncommitted in $top; they will not reach the server clone"
        actions+=("Commit source changes you want on the server, then select that commit with --revision.")
      else
        ok "source changes" "working tree clean"
      fi
    fi
  fi
fi

if [ ${#actions[@]} -gt 0 ]; then
  printf '\nManual actions:\n'
  printf '  - %s\n' "${actions[@]}"
fi

printf '\n'
if [ $failures -gt 0 ]; then
  printf 'Result: %s required prerequisite(s) missing\n' "$failures"
  exit 1
fi
printf 'Result: required prerequisites are met\n'
