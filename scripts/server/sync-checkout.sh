#!/usr/bin/env bash
# Clone or fetch the Nidrew source into the server checkout and select one
# committed revision. Run as the account that owns the checkout (nidrew).
# Preserves the source, local changes, and commits not on any branch or tag.
set -u

source_path=/mnt/c/projects/nidrew
checkout="$HOME/nidrew"
revision=HEAD

usage() {
  cat <<'EOF'
Usage: sync-checkout.sh [--source PATH] [--checkout PATH] [--revision REV]

Clone the source repository into the checkout with independent Git data, or
fetch into an existing clone, then check out REV detached and record it as
refs/nidrew/selected. Only committed source content is transferred.

  --source PATH     Source Git repository (default: /mnt/c/projects/nidrew)
  --checkout PATH   Server checkout (default: $HOME/nidrew)
  --revision REV    Revision to select, resolved in the source (default: HEAD)

Refuses, without changing anything, when the checkout path holds other
content, has another origin, has uncommitted changes or an operation in
progress, or when selecting would leave a commit off every branch and tag.

Exit status: 0 on success, 1 when refused or failed, 2 on usage errors.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --source | --checkout | --revision)
      if [ $# -lt 2 ]; then
        printf 'Missing value for %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      case $1 in
        --source) source_path=$2 ;;
        --checkout) checkout=$2 ;;
        --revision) revision=$2 ;;
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

refuse() {
  printf 'Refused: %s\n' "$1" >&2
  [ $# -lt 2 ] || printf 'Resolve: %s\n' "$2" >&2
  exit 1
}

# The source is usually owned by another user on /mnt/c. Trust exactly that
# repository for these commands instead of changing global Git configuration.
# Local commands check the worktree path. Fetches run upload-pack in the .git
# directory, and Git drops -c settings for it, so the clone's remote config
# names an upload-pack command that trusts the source.
src_git() { git -c "safe.directory=$source_path" -C "$source_path" "$@"; }
co_git() { git -C "$checkout" "$@"; }
upload_pack="git -c safe.directory=$(printf %q "$source_path/.git") upload-pack"

commit=$(src_git rev-parse --verify --quiet "$revision^{commit}") ||
  refuse "$revision does not name a commit in $source_path" \
    "commit the work in the source and pass an existing revision"

source_changes=$({
  src_git -c core.autocrlf=true -c core.safecrlf=false diff --name-only HEAD
  src_git ls-files --others --exclude-standard
} 2>/dev/null | grep -c .)
if [ "$source_changes" -gt 0 ]; then
  printf 'Note: %s uncommitted change(s) in the source are not transferred.\n' "$source_changes"
fi

if [ -e "$checkout" ] && ! { [ -d "$checkout" ] && [ -z "$(ls -A "$checkout")" ]; }; then
  if [ "$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$checkout" 2>/dev/null && pwd -P)" ]; then
    refuse "$checkout exists and is not a Git checkout" \
      "move its contents elsewhere or pass another --checkout"
  fi

  origin=$(co_git config --get remote.origin.url || true)
  [ "$origin" = "$source_path" ] ||
    refuse "$checkout origin is ${origin:-unset}, not $source_path" \
      "pass the matching --source, or fix the origin with: git -C $checkout remote set-url origin $source_path"

  git_dir=$(co_git rev-parse --absolute-git-dir)
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
    [ ! -e "$git_dir/$marker" ] ||
      refuse "a Git operation is in progress in $checkout ($marker)" \
        "finish or abort it in $checkout, then rerun"
  done

  changes=$(co_git status --porcelain)
  [ -z "$changes" ] ||
    refuse "$checkout has uncommitted changes:
$changes" "commit, stash, or remove them in $checkout, then rerun"

  [ "$(co_git config --get remote.origin.uploadpack)" = "$upload_pack" ] ||
    co_git config remote.origin.uploadpack "$upload_pack"
  co_git fetch --quiet --prune --tags origin ||
    refuse "fetching from $source_path failed" "check that this account can read $source_path"
else
  git clone --quiet --no-local --no-checkout --upload-pack "$upload_pack" \
    --config "remote.origin.uploadpack=$upload_pack" "$source_path" "$checkout" ||
    refuse "cloning $source_path into $checkout failed" \
      "check that this account can read $source_path and write $(dirname "$checkout")"
fi

# A commit only reachable from a detached source HEAD is not on a fetched ref.
if ! co_git cat-file -e "$commit^{commit}" 2>/dev/null; then
  co_git fetch --quiet origin "$commit" ||
    refuse "could not fetch $commit from $source_path"
fi

head=$(co_git rev-parse --verify --quiet HEAD || true)
if [ "$head" = "$commit" ] && ! co_git symbolic-ref -q HEAD >/dev/null; then
  co_git update-ref -m "select $revision" refs/nidrew/selected "$commit"
  printf 'Checkout %s already at %s (%s).\n' "$checkout" "$commit" "$(co_git log -1 --format=%s "$commit")"
  exit 0
fi

if [ -n "$head" ] && [ -z "$(co_git for-each-ref --count=1 --contains "$head")" ]; then
  refuse "$checkout HEAD $head is not on any branch or tag; selecting $commit would orphan it" \
    "keep it with: git -C $checkout branch <name> $head, then rerun"
fi

co_git checkout --quiet --detach "$commit" ||
  refuse "checking out $commit in $checkout failed"
co_git update-ref -m "select $revision" refs/nidrew/selected "$commit"
printf 'Checkout %s selected %s (%s) from %s %s.\n' \
  "$checkout" "$commit" "$(co_git log -1 --format=%s "$commit")" "$source_path" "$revision"
