#!/usr/bin/env bash
# Scaffold a compliant Agent Skill plus its research log.
# Usage: new-skill.sh <name> [--full]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "usage: new-skill.sh <name> [--full]" >&2
  echo "  name     lowercase letters, digits, hyphens; must match directory name" >&2
  echo "  --full   also create scripts/, references/, assets/" >&2
  exit 1
}

name="${1:-}"
mode="${2:-}"
[ -n "$name" ] || usage

if ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ "${#name}" -gt 64 ]; then
  echo "error: invalid name '$name'" >&2
  echo "use lowercase letters, digits and single hyphens, 1-64 chars" >&2
  exit 1
fi

skill_dir="$repo_root/.commandcode/skills/$name"
if [ -e "$skill_dir" ]; then
  echo "error: $skill_dir already exists" >&2
  exit 1
fi

mkdir -p "$skill_dir"
if [ "$mode" = "--full" ]; then
  mkdir -p "$skill_dir/scripts" "$skill_dir/references" "$skill_dir/assets"
  touch "$skill_dir/scripts/.gitkeep" "$skill_dir/references/.gitkeep" "$skill_dir/assets/.gitkeep"
fi

title="$(printf '%s' "$name" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')"

cat > "$skill_dir/SKILL.md" <<EOF
---
name: $name
description: <What it does in one sentence.> Use when <trigger phrase or task shape>. Don't use for <adjacent task it must not fire on>.
metadata:
  version: "0.1"
---

# $title

## Preconditions

- <what must be true before the skill runs>

## Steps

1. <first action, with the exact command>
2. <next action>
3. <validation step>

## Gotchas

- <project-specific fact the agent would otherwise get wrong>

## Checklist

- [ ] <verifiable outcome>

## Dependencies

- <sibling skill or bundled file this skill relies on, or "none">
EOF

mkdir -p "$repo_root/research"
research_file="$repo_root/research/$name.md"
if [ -e "$research_file" ]; then
  echo "note: research/$name.md exists, left untouched"
else
  sed "s/<skill-name>/$name/g; s/YYYY-MM-DD/$(date +%F)/" \
    "$repo_root/research/_template.md" > "$research_file"
fi

echo "created $skill_dir/SKILL.md"
[ -f "$research_file" ] && echo "created $research_file"
echo ""
echo "Next:"
echo "  1. Fill research/$name.md (web search + primary sources are mandatory — see AI.md)"
echo "  2. Write the body: frontmatter first, then numbered steps"
echo "  3. Run scripts/validate-skills.sh"
