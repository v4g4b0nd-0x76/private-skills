#!/usr/bin/env bash
# Validate every skill in this repo against the agentskills.io rules in AI.md.
# Usage: validate-skills.sh [skills-dir]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_dir="${1:-$repo_root/.commandcode/skills}"

errors=0
warnings=0
checked=0

fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN:  $*" >&2; warnings=$((warnings + 1)); }

fm_field() {
  awk -v key="$1" '
    /^---[[:space:]]*$/ { fm++; if (fm == 2) exit; next }
    fm == 1 && index($0, key ":") == 1 {
      line = $0
      sub("^" key ":[[:space:]]*", "", line)
      print line
      exit
    }
  ' "$2"
}

[ -d "$skills_dir" ] || { echo "error: skills directory not found: $skills_dir" >&2; exit 1; }

shopt -s nullglob
for dir in "$skills_dir"/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  file="$dir/SKILL.md"
  checked=$((checked + 1))

  if [ ! -f "$file" ]; then
    fail "$name: missing SKILL.md"
    continue
  fi

  if [ "$(head -n 1 "$file")" != "---" ]; then
    fail "$name: SKILL.md must start with YAML frontmatter"
    continue
  fi

  fm_name="$(fm_field name "$file")"
  desc="$(fm_field description "$file")"

  [ -n "$fm_name" ] || fail "$name: missing 'name' in frontmatter"
  [ "$fm_name" = "$name" ] || fail "$name: name '$fm_name' must equal directory name"

  if ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    fail "$name: name must be lowercase letters, digits and single hyphens"
  fi
  [ "${#name}" -le 64 ] || fail "$name: name exceeds 64 characters"

  [ -n "$desc" ] || fail "$name: missing 'description' in frontmatter"
  desc_len="$(printf '%s' "$desc" | wc -m | tr -d ' ')"
  [ "$desc_len" -le 1024 ] || fail "$name: description is $desc_len chars (max 1024)"
  [ "$desc_len" -ge 40 ] || warn "$name: description is very short ($desc_len chars) — discovery will suffer"
  case "$desc" in
    "Helps with"*|"helps with"*) fail "$name: description must not start with 'Helps with'" ;;
  esac
  case "$desc" in
    *"Use when"*|*"Use for"*|*"use when"*|*"use for"*) ;;
    *) warn "$name: description has no 'Use when ...' trigger" ;;
  esac
  case "$desc" in
    *"Don't use"*|*"Do not use"*|*"don't use"*) ;;
    *) warn "$name: description has no negative trigger (\"Don't use for ...\")" ;;
  esac

  body_lines="$(awk '/^---[[:space:]]*$/ { fm++; next } fm >= 2 { n++ } END { print n + 0 }' "$file")"
  [ "$body_lines" -le 500 ] || fail "$name: body is $body_lines lines (max 500)"

  for doc in README.md CHANGELOG.md INSTALL.md INSTALLATION_GUIDE.md; do
    [ -f "$dir/$doc" ] && fail "$name: remove $doc from the skill directory (keep docs in AI.md)"
  done

  while IFS= read -r link; do
    [ -n "$link" ] || continue
    path="${link#(}"
    path="${path%)}"
    [ -f "$dir/$path" ] || fail "$name: broken relative link '$path'"
  done < <(grep -oE '\((references|assets|scripts)/[^)]+\)' "$file" || true)

  for script in "$dir"/scripts/*; do
    [ -f "$script" ] || continue
    case "$(head -n 1 "$script")" in
      *bash*|*sh*)
        bash -n "$script" 2>/dev/null || fail "$name: syntax error in scripts/$(basename "$script")"
        [ -x "$script" ] || warn "$name: scripts/$(basename "$script") is not executable"
        ;;
    esac
  done

  if [ ! -f "$repo_root/research/$name.md" ]; then
    warn "$name: no research/$name.md (mandatory per AI.md)"
  fi
done

echo ""
echo "checked $checked skill(s): $errors error(s), $warnings warning(s)"

[ "$errors" -eq 0 ] || exit 1
