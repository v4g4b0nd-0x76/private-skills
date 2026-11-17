#!/usr/bin/env bash
# Lint skill descriptions for triggering quality, without running an agent.
#
# This is the cheap gate. It catches the mechanical failures that make a skill
# invisible or over-eager. Actual triggering must be measured with evals
# (evals/<skill>/eval_queries.json) using scripts/trigger-eval.sh.
#
# Usage: description-lint.sh [skills-dir]
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_dir="${1:-$repo_root/.commandcode/skills}"

errors=0; warnings=0; checked=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); return 0; }
warn() { echo "WARN:  $*" >&2; warnings=$((warnings + 1)); return 0; }

desc_of() {
  awk '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 && /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

# Strip the trailing "Don't use ..." clause, leaving the positive scope.
positive_only() {
  printf '%s' "$1" | sed -E "s/[.]? *(Don't|Do not|don't) use.*$//"
}

[ -d "$skills_dir" ] || { echo "error: no skills dir: $skills_dir" >&2; exit 1; }

echo "== description lint =="
shopt -s nullglob

for dir in "$skills_dir"/*/; do
  dir="${dir%/}"; name="$(basename "$dir")"; file="$dir/SKILL.md"
  [ -f "$file" ] || continue
  checked=$((checked + 1))

  desc="$(desc_of "$file")"
  if [ -z "$desc" ]; then fail "$name: no description"; continue; fi

  len="$(printf '%s' "$desc" | wc -m | tr -d ' ')"
  [ "$len" -le 1024 ] || fail "$name: description $len chars (max 1024)"

  # Trigger words: the agent matches against what a user would say.
  case "$desc" in
    *Use\ when*|*use\ when*|*Use\ for*|*use\ for*) ;;
    *) fail "$name: no 'Use when/for' trigger clause" ;;
  esac

  # Negative trigger: near-miss protection. Without one, a skill fires on
  # adjacent tasks and steals work from the skill that should handle them.
  case "$desc" in
    *Don\'t\ use*|*Do\ not\ use*|*don\'t\ use*) ;;
    *) fail "$name: no negative trigger (\"Don't use for ...\") — near-misses will false-trigger" ;;
  esac

  # Starting with "Helps with" is the canonical vague description.
  case "$desc" in
    "Helps with"*|"helps with"*) fail "$name: starts with 'Helps with' — name verbs and artifacts" ;;
  esac

  # A description that only names a topic, not an action, under-triggers.
  pos="$(positive_only "$desc")"
  case "$pos" in
    *[Gg]enerate*|*[Ww]rite*|*[Tt]est*|*[Aa]udit*|*[Ii]nventory*|*[Rr]eview*|*[Rr]un*|*[Bb]uild*|*[Cc]heck*|*[Ff]ind*|*[Mm]ap*|*[Rr]oute*|*[Pp]rofile*|*[Ii]nstall*|*[Vv]alidate*|*[Cc]reate*|*[Dd]esign*|*[Ee]xecute*|*[Rr]educe*)
      ;;
    *) warn "$name: no action verb in the positive clause — may under-trigger" ;;
  esac

  # Length sanity: too short under-triggers, too long dilutes.
  [ "$len" -ge 80 ] || warn "$name: description only $len chars — add scope detail"
  [ "$len" -le 700 ] || warn "$name: description $len chars — consider trimming to keep triggering sharp"

  # Overlap: two skills claiming the same verbs+domain is a routing hazard.
done

# Two skills claiming the same domain word suggests ambiguous routing.
overlap_dir="$(mktemp -d)"
trap 'rm -rf "$overlap_dir"' EXIT

for dir in "$skills_dir"/*/; do
  name="$(basename "${dir%/}")"
  [ -f "$dir/SKILL.md" ] || continue
  desc_of "$dir/SKILL.md" > "$overlap_dir/$name.desc"
done

for a_file in "$overlap_dir"/*.desc; do
  a="$(basename "$a_file" .desc)"
  for b_file in "$overlap_dir"/*.desc; do
    b="$(basename "$b_file" .desc)"
    # Compare each unordered pair once.
    [ "$a" \< "$b" ] || continue
    # Members of the same package (devflow, devflow-plan, ...) are meant to share
    # vocabulary; their routing is handled by the orchestrator, not by triggering.
    case "$a:$b" in
      devflow:devflow-*) continue ;;
      devflow-*:devflow-*) continue ;;
      # Documented split: authorized abuse vs correctness under load. Each
      # names the other in its negative trigger, so the overlap is deliberate.
      backend-security-test:thirdparty-e2e) continue ;;
      # Documented split: sub-µs dual-gate campaign vs general systems perf.
      rust-submicrosecond-refactor:rust-systems-perf) continue ;;
    esac
    common=""
    for word in security testing performance backlog heap cache load e2e migration; do
      if grep -qiw "$word" "$a_file" 2>/dev/null && grep -qiw "$word" "$b_file" 2>/dev/null; then
        common="$common $word"
      fi
    done
    if [ -n "$common" ]; then
      warn "possible overlap $a <-> $b on:$common — confirm each has a distinct negative trigger"
    fi
  done
done

echo ""
echo "checked $checked description(s): $errors error(s), $warnings warning(s)"
[ "$errors" -eq 0 ] || exit 1
