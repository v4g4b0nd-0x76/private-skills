#!/usr/bin/env bash
# Scan the current diff for credentials, private keys, debug leftovers, and TODOs.
# Usage: check-diff.sh [project-root]
# Exit 1 when a credential or private key is found.
set -euo pipefail

root="${1:-.}"

git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "warn: $root is not a git repository — diff scan skipped" >&2
  exit 0
}

added="$(mktemp)"
trap 'rm -f "$added"' EXIT

git -C "$root" diff --no-color -U0 HEAD 2>/dev/null | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^@@/ {
    match($0, /\+[0-9]+/)
    n = substr($0, RSTART + 1, RLENGTH - 1) + 0
    next
  }
  /^\+/ && !/^\+\+\+/ {
    print file ":" n ":" substr($0, 2)
    n++
  }
' > "$added"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  awk -v f="$file" '{ print f ":new:" $0 }' "$root/$file" >> "$added"
done < <(git -C "$root" ls-files --others --exclude-standard)

if [ ! -s "$added" ]; then
  echo "no added lines to scan"
  exit 0
fi

scan() {
  local label="$1" pattern="$2"
  grep -E -i -- "$pattern" "$added" | sed "s/^/$label /" || true
}

secrets="$(scan "SECRET:" '(BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|(api[_-]?key|secret|password|passwd|access[_-]?token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,})')"
debugs="$(scan "DEBUG:" '(console\.log|debugger;|pdb\.set_trace|binding\.pry|fmt\.Println\(|var_dump\()')"
todos="$(scan "TODO:" '(TODO|FIXME|XXX)')"

secret_count=0
if [ -n "$secrets" ]; then
  echo "$secrets"
  secret_count="$(printf '%s\n' "$secrets" | wc -l | tr -d ' ')"
fi

if [ -n "$debugs" ]; then
  echo "$debugs"
fi

if [ -n "$todos" ]; then
  echo "$todos"
  echo "note: $(printf '%s\n' "$todos" | wc -l | tr -d ' ') TODO/FIXME marker(s) in added lines"
fi

if [ "$secret_count" -gt 0 ]; then
  echo "diff scan failed: $secret_count possible credential(s) or private key(s)" >&2
  exit 1
fi

echo "diff scan passed: no credentials or private keys"
