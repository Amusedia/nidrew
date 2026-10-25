# Managed-file helpers sourced by the Debian setup scripts. A managed file is
# recorded with its last-applied checksum in $state_dir/managed.sha256 and its
# previous version in $state_dir/previous/. The caller defines state_dir and
# refuse(), plans every file with plan_file, stops when conflicts is nonzero,
# and then activates with replace and record.

conflicts=0
declare -A action

conflict() {
  printf 'Conflict: %s\n  Resolve: %s\n' "$1" "$2" >&2
  conflicts=$((conflicts + 1))
}

recorded_sum() { awk -v p="$1" '$2 == p { s = $1 } END { print s }' "$state_dir/managed.sha256" 2>/dev/null; }

# plan_file TARGET CANDIDATE SOURCE sets action[TARGET] to installed, unchanged,
# or updated, or reports a conflict naming SOURCE as the place for changes.
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

# apply_file TARGET CANDIDATE keeps the previous version of an updated file,
# installs the candidate unless unchanged, records it, and reports the action.
apply_file() {
  local target=$1 candidate=$2
  [ "${action[$target]}" != updated ] || cp -p "$target" "$state_dir/previous/${target##*/}"
  [ "${action[$target]}" = unchanged ] || replace "$target" "$candidate"
  record "$target"
  printf '%s %s\n' "${action[$target]}" "$target"
}
