#!/usr/bin/env bash
# Report the state of the nidrew account, its storage, and the server checkout.
# Changes nothing. Run as root (through sudo) to inspect another account.
set -u

account=nidrew
home=/home/nidrew
checkout=$home/nidrew
artifacts=$home/artifacts
failures=0

report() { printf '[%s] %s: %s\n' "$1" "$2" "$3"; }
ok() { report ' ok ' "$1" "$2"; }
fail() {
  report 'FAIL' "$1" "$2"
  failures=$((failures + 1))
}
as_account() { runuser -u "$account" -- env HOME="$home" "$@"; }

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run as root to inspect %s: sudo bash %s\n' "$account" "$0" >&2
  exit 1
fi

if ! id "$account" >/dev/null 2>&1; then
  fail account "$account does not exist; run provision-account.sh"
  exit 1
fi
groups=$(id -nG "$account")
ok account "$(id "$account")"
case " $groups " in
  *" sudo "* | *" admin "* | *" wheel "*) fail sudo "$account is in an administrative group: $groups" ;;
  *)
    if sudo -l -U "$account" 2>/dev/null | grep -q 'may run the following'; then
      fail sudo "$account has sudo privileges"
    else
      ok sudo "$account has no sudo privileges"
    fi
    ;;
esac

for entry in "$home:700" "$artifacts:750"; do
  path=${entry%:*}
  actual="$(stat -c '%U:%G %a' "$path" 2>/dev/null)"
  if [ "$actual" = "$account:$account ${entry#*:}" ]; then
    ok directory "$path $actual"
  else
    fail directory "$path is '${actual:-missing}', expected $account:$account ${entry#*:}"
  fi
done

if ! as_account git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1; then
  fail checkout "$checkout is not a Git checkout readable by $account"
else
  ok checkout "$checkout owned by $(stat -c %U:%G "$checkout")"
  head=$(as_account git -C "$checkout" rev-parse HEAD)
  selected=$(as_account git -C "$checkout" rev-parse --verify -q refs/nidrew/selected)
  if [ "$head" = "$selected" ]; then
    ok revision "HEAD is the selected $selected"
  else
    fail revision "HEAD $head differs from refs/nidrew/selected ${selected:-unset}"
  fi
  if [ -e "$checkout/.git/objects/info/alternates" ]; then
    fail "git data" "objects borrow from another repository (alternates)"
  else
    ok "git data" "independent object store"
  fi
  origin=$(as_account git -C "$checkout" config --get remote.origin.url)
  if as_account git -C "$checkout" fetch --dry-run --quiet origin 2>/dev/null; then
    ok fetch "$account can fetch from $origin"
  else
    fail fetch "$account cannot fetch from $origin"
  fi
  changes=$(as_account git -C "$checkout" status --porcelain | grep -c .)
  if [ "$changes" -eq 0 ]; then
    ok "local changes" "none"
  else
    report 'warn' "local changes" "$changes uncommitted in $checkout"
  fi
fi

printf '\n'
if [ $failures -gt 0 ]; then
  printf 'Result: %s problem(s) found\n' "$failures"
  exit 1
fi
printf 'Result: account and checkout are ready\n'
