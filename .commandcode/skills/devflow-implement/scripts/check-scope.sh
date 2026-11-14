#!/usr/bin/env bash
# Compare working-tree changes against the plan's "Files to touch" list.
# Usage: check-scope.sh [project-root]
# Exit 1 when changes exist outside the plan.
set -euo pipefail

root="${1:-.}"
plan="$root/.devflow/plan.md"

[ -f "$plan" ] || { echo "ERROR: missing $plan" >&2; exit 1; }

git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "warn: $root is not a git repository — scope check skipped" >&2
  exit 0
}

section() {
  awk -v want="$1" '
    /^## / { title = substr($0, 4); gsub(/[[:space:]]+$/, "", title);
             in_section = (tolower(title) == tolower(want)); next }
    in_section { print }
  ' "$2"
}

allowed=()
while IFS= read -r entry; do
  entry="${entry#-}"
  entry="${entry#"${entry%%[![:space:]]*}"}"
  entry="${entry%%#*}"
  entry="${entry%% — *}"
  entry="${entry%% -- *}"
  entry="$(printf '%s' "$entry" | tr -d '`' | tr -d '[:space:]')"
  [ -n "$entry" ] && allowed+=("$entry")
done < <(section "Files to touch" "$plan" | grep '^-[[:space:]]')

if [ "${#allowed[@]}" -eq 0 ]; then
  echo "ERROR: plan has no Files to touch entries" >&2
  exit 1
fi

changed_file_list="$(mktemp)"
trap 'rm -f "$changed_file_list"' EXIT

git -C "$root" diff --name-only HEAD 2>/dev/null > "$changed_file_list" || true
git -C "$root" ls-files --others --exclude-standard >> "$changed_file_list"

sort -u "$changed_file_list" -o "$changed_file_list"

out_of_scope=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    .devflow/*) continue ;;
  esac

  match=0
  for entry in "${allowed[@]}"; do
    entry="${entry%/}"
    if [ "$file" = "$entry" ] || [[ "$file" == "$entry"/* ]]; then
      match=1
      break
    fi
  done

  if [ "$match" -eq 0 ]; then
    echo "OUT OF SCOPE: $file" >&2
    out_of_scope=$((out_of_scope + 1))
  fi
done < "$changed_file_list"

if [ "$out_of_scope" -gt 0 ]; then
  echo "scope check failed: $out_of_scope file(s) outside the approved plan" >&2
  echo "Either revert them, or ask the user to add them to the plan." >&2
  exit 1
fi

echo "scope check passed: all changes are inside the plan's file list"
