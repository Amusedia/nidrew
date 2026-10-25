#!/usr/bin/env bash
# Tests for sync-checkout.sh using temporary source and checkout repositories.
# Usage: scripts/server/tests/sync-checkout-test.sh
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
sync="$script_dir/../sync-checkout.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

passed=0
failed=0
output=
status=0

source_repo="$work/source"
checkout="$work/checkout"

commit_source() {
  printf '%s\n' "$1" >"$source_repo/file.txt"
  git -C "$source_repo" add file.txt
  git -C "$source_repo" commit -q -m "$1"
  git -C "$source_repo" rev-parse HEAD
}

reset_repos() {
  rm -rf "$source_repo" "$checkout"
  git init -q -b main "$source_repo"
  first=$(commit_source one)
}

run_sync() {
  output=$(bash "$sync" --source "$source_repo" --checkout "$checkout" "$@" 2>&1)
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

expect_equal() {
  if [ "$1" = "$2" ]; then return 0; fi
  printf '  expected %s, got %s (%s)\n' "$2" "$1" "$3"
  return 1
}

checkout_head() { git -C "$checkout" rev-parse HEAD; }

check() {
  local name=$1
  shift
  reset_repos
  if "$@"; then
    passed=$((passed + 1))
    printf 'pass: %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\n%s\n' "$name" "$output"
  fi
}

t_fresh_clone() {
  run_sync
  expect_status 0 && expect_output "selected $first" &&
    expect_equal "$(checkout_head)" "$first" "checkout HEAD" &&
    expect_equal "$(git -C "$checkout" rev-parse refs/nidrew/selected)" "$first" "recorded revision" &&
    expect_equal "$(git -C "$checkout" config remote.origin.url)" "$source_repo" "origin" &&
    [ ! -e "$checkout/.git/objects/info/alternates" ]
}
check "fresh clone selects and records the revision" t_fresh_clone

t_matching_rerun() {
  run_sync
  run_sync
  expect_status 0 && expect_output "already at $first"
}
check "matching rerun leaves the checkout unchanged" t_matching_rerun

t_new_commit() {
  run_sync
  second=$(commit_source two)
  run_sync
  expect_status 0 && expect_output "selected $second" &&
    expect_equal "$(checkout_head)" "$second" "checkout HEAD"
}
check "rerun fetches and selects a new commit" t_new_commit

t_explicit_revision() {
  second=$(commit_source two)
  run_sync --revision "$first"
  expect_status 0 && expect_equal "$(checkout_head)" "$first" "checkout HEAD"
}
check "explicit revision is selected" t_explicit_revision

t_detached_source_commit() {
  git -C "$source_repo" checkout -q --detach
  detached=$(commit_source detached)
  run_sync
  expect_status 0 && expect_equal "$(checkout_head)" "$detached" "checkout HEAD"
}
check "commit only reachable from a detached source HEAD is fetched" t_detached_source_commit

t_unknown_revision() {
  run_sync --revision no-such-ref
  expect_status 1 && expect_output "no-such-ref does not name a commit"
}
check "unknown revision is refused" t_unknown_revision

t_source_untouched() {
  printf 'local edit\n' >"$source_repo/uncommitted.txt"
  before=$(git -C "$source_repo" status --porcelain)
  run_sync
  expect_status 0 &&
    expect_equal "$(git -C "$source_repo" status --porcelain)" "$before" "source status" &&
    [ ! -e "$checkout/uncommitted.txt" ] &&
    expect_output "1 uncommitted change(s) in the source are not transferred"
}
check "uncommitted source edits stay in the source and are reported" t_source_untouched

t_dirty_checkout() {
  run_sync
  commit_source two >/dev/null
  printf 'server work\n' >"$checkout/notes.txt"
  run_sync
  expect_status 1 && expect_output "uncommitted changes" &&
    expect_equal "$(checkout_head)" "$first" "checkout HEAD" &&
    [ -f "$checkout/notes.txt" ]
}
check "local changes in the checkout are preserved" t_dirty_checkout

t_unreachable_commit() {
  run_sync
  printf 'server commit\n' >"$checkout/server.txt"
  git -C "$checkout" add server.txt
  git -C "$checkout" commit -q -m "server commit"
  local server_commit
  server_commit=$(checkout_head)
  commit_source two >/dev/null
  run_sync
  expect_status 1 && expect_output "not on any branch or tag" &&
    expect_equal "$(checkout_head)" "$server_commit" "checkout HEAD"
}
check "commits not on any ref are preserved" t_unreachable_commit

t_local_branch_kept() {
  run_sync
  git -C "$checkout" switch -q -c server-work
  printf 'server commit\n' >"$checkout/server.txt"
  git -C "$checkout" add server.txt
  git -C "$checkout" commit -q -m "server commit"
  run_sync
  expect_status 0 && expect_equal "$(checkout_head)" "$first" "checkout HEAD" &&
    git -C "$checkout" rev-parse --verify -q server-work >/dev/null
}
check "local branches remain when another revision is selected" t_local_branch_kept

t_not_a_repository() {
  mkdir -p "$checkout"
  printf 'keep\n' >"$checkout/existing.txt"
  run_sync
  expect_status 1 && expect_output "exists and is not a Git checkout" &&
    [ -f "$checkout/existing.txt" ]
}
check "non-repository content at the checkout path is preserved" t_not_a_repository

t_other_origin() {
  git init -q "$checkout"
  git -C "$checkout" remote add origin /elsewhere
  run_sync
  expect_status 1 && expect_output "origin is /elsewhere"
}
check "checkout with a different origin is refused" t_other_origin

t_operation_in_progress() {
  run_sync
  : >"$checkout/.git/MERGE_HEAD"
  run_sync
  expect_status 1 && expect_output "operation is in progress"
}
check "in-progress Git operation is refused" t_operation_in_progress

t_usage() {
  run_sync --bogus
  expect_status 2 && expect_output "Usage:"
}
check "unknown argument is a usage error" t_usage

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
