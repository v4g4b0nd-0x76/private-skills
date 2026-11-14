#!/usr/bin/env bash
# Install this repo's skills into any supported coding agent.
#
# Usage:
#   install-skills.sh <target> [--agent LIST] [--scope S] [--link] [--force] [--dry-run]
#
#   <target>        a project directory, or --user for the home directory
#   --agent LIST    comma-separated: commandcode,codex,cursor,claude,gemini,agents
#                   (default: every agent whose config dir exists, else all)
#   --scope S       project | user  (default: project for a dir, user for --user)
#   --link          symlink instead of copy (edit here, changes apply live)
#   --force         overwrite existing skills
#   --dry-run       print the plan, write nothing
#
# Discovery paths are documented per agent in references/agent-targets.md and
# verified against vendor docs on 2026-11-14. Re-verify before trusting them.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/.commandcode/skills"

target=""
agents=""
scope=""
link_mode=0
force=0
dry=0
autodetect=0

usage() {
  cat >&2 <<'EOF'
usage: install-skills.sh <target|--user> [options]

  --agent LIST   commandcode,codex,cursor,claude,gemini,agents (comma-separated)
  --scope S      project | user
  --link         symlink instead of copy
  --force        overwrite existing skills
  --dry-run      print the plan, write nothing
  --list         show the target matrix and exit

Targets:
  .commandcode/skills  Command Code (project)   ~/.commandcode/skills  (user)
  .agents/skills       Codex, Cursor, Gemini    ~/.agents/skills       (user)
  .codex/skills        Codex compatibility      ~/.codex/skills        (user)
  .cursor/skills       Cursor                   ~/.cursor/skills       (user)
  .claude/skills       Claude Code              ~/.claude/skills       (user)
  .gemini/skills       Gemini CLI               ~/.gemini/skills       (user)
EOF
  exit 1
}

print_matrix() {
  cat <<'EOF'
Verified discovery paths (vendor docs, 2026-11-14):

  agent          project path        user path            notes
  -------------- ------------------- -------------------- ------------------------------
  commandcode    .commandcode/skills ~/.commandcode/skills
  codex          .agents/skills      ~/.agents/skills     scans upward to repo root
  cursor         .agents/skills      ~/.agents/skills     also reads .claude/.codex
  gemini         .agents/skills      ~/.agents/skills     .agents wins over .gemini
  claude         .claude/skills      ~/.claude/skills     spec frontmatter only on upload
  agents (shared).agents/skills      ~/.agents/skills     the interoperable default

.agents/skills is read natively by Codex, Cursor and Gemini. Prefer it: one copy
covers three agents. Claude Code is the only one needing a separate path.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user) target="__USER__"; [ -z "$scope" ] && scope="user"; shift ;;
    --agent) agents="${2:-}"; shift 2 ;;
    --scope) scope="${2:-}"; shift 2 ;;
    --link) link_mode=1; shift ;;
    --force) force=1; shift ;;
    --dry-run) dry=1; shift ;;
    --list) print_matrix; exit 0 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *)
      if [ -n "$target" ] && [ "$target" != "__USER__" ]; then
        echo "error: multiple targets given ('$target', '$1')" >&2; usage
      fi
      target="$1"; shift ;;
  esac
done

[ -n "$target" ] || usage
[ -d "$source_dir" ] || { echo "error: no skills in $source_dir" >&2; exit 1; }

if [ "$target" = "__USER__" ]; then
  base="$HOME"
  scope="${scope:-user}"
else
  [ -d "$target" ] || { echo "error: target project not found: $target" >&2; exit 1; }
  base="$target"
  scope="${scope:-project}"
fi

case "$scope" in
  project|user) ;;
  *) echo "error: --scope must be project or user" >&2; exit 1 ;;
esac

if [ "$scope" = "user" ] && [ "$target" != "__USER__" ]; then
  echo "note: --scope user installs into \$HOME, not into $target"
  base="$HOME"
fi

# --- resolve destinations ------------------------------------------------


declare_path() {
  # agent scope -> relative path
  case "$1:$2" in
    commandcode:project) echo ".commandcode/skills" ;;
    commandcode:user)    echo ".commandcode/skills" ;;
    agents:project|agents:user) echo ".agents/skills" ;;
    codex:*)   echo ".codex/skills" ;;
    cursor:*)  echo ".cursor/skills" ;;
    claude:*)  echo ".claude/skills" ;;
    gemini:*)  echo ".gemini/skills" ;;
    *) echo "" ;;
  esac
}

ALL_AGENTS="commandcode agents codex cursor claude gemini"

if [ -z "$agents" ]; then
  autodetect=1
  # Default: agents whose config already exists in this scope; else the shared set.
  detected=""
  for a in $ALL_AGENTS; do
    p="$(declare_path "$a" "$scope")"
    [ -n "$p" ] || continue
    case "$a" in
      commandcode) [ -d "$base/.commandcode" ] && detected="$detected $a" ;;
      agents)      [ -d "$base/.agents" ] && detected="$detected $a" ;;
      codex)       { [ -d "$base/.codex" ] || command -v codex >/dev/null 2>&1; } && detected="$detected $a" ;;
      cursor)      { [ -d "$base/.cursor" ] || command -v cursor >/dev/null 2>&1; } && detected="$detected $a" ;;
      claude)      { [ -d "$base/.claude" ] || command -v claude >/dev/null 2>&1; } && detected="$detected $a" ;;
      gemini)      { [ -d "$base/.gemini" ] || command -v gemini >/dev/null 2>&1; } && detected="$detected $a" ;;
    esac
  done
  if [ -n "${detected// /}" ]; then
    agents="$(printf '%s' "$detected" | tr ' ' ',' | sed 's/^,//')"
    echo "detected agents: $agents"
    # Collapse shared-path agents into one copy. Codex, Cursor and Gemini all
    # read .agents/skills natively, so installing all three separately would
    # create three identical directory trees for no benefit.
    shared=0
    for a in codex cursor gemini; do
      case ",$agents," in *",$a,"*) shared=$((shared + 1)) ;; esac
    done
    if [ "$shared" -ge 2 ] && [ "$autodetect" -eq 1 ]; then
      new=""
      for a in $(printf '%s' "$agents" | tr ',' ' '); do
        case "$a" in
          codex|cursor|gemini) new="$new agents" ;;
          *) new="$new $a" ;;
        esac
      done
      agents="$(printf '%s\n' $new | awk '!seen[$0]++' | paste -sd, -)"
      echo "collapsed to:     $agents  (shared .agents/skills covers codex, cursor, gemini)"
      echo "                  use --agent cursor,codex,gemini for separate native dirs"
    fi
  else
    agents="agents"
    echo "no agent config found; installing to the shared .agents/skills target"
  fi
fi

# De-duplicate: agents and cursor/gemini share .agents/skills only if asked
# explicitly; keep each requested agent's own canonical path.
dest_dirs=""
IFS=',' read -r -a agent_list <<< "$agents"
for a in "${agent_list[@]}"; do
  a="$(printf '%s' "$a" | tr -d '[:space:]')"
  [ -n "$a" ] || continue
  p="$(declare_path "$a" "$scope")"
  if [ -z "$p" ]; then
    echo "error: unknown agent '$a' (try --list)" >&2; exit 1
  fi
  dest_dirs="$dest_dirs $p"
done

# Unique, preserve order.
uniq_dests=""
for d in $dest_dirs; do
  case " $uniq_dests " in *" $d "*) ;; *) uniq_dests="$uniq_dests $d" ;; esac
done

if ! bash "$repo_root/scripts/validate-skills.sh" >/dev/null 2>&1; then
  echo "error: validation failed — run scripts/validate-skills.sh and fix errors first" >&2
  exit 1
fi

echo ""
echo "skills:  $(ls -d "$source_dir"/*/ 2>/dev/null | wc -l | tr -d ' ') in $source_dir"
echo "target:  $base"
echo "scope:   $scope"
echo "mode:    $([ "$link_mode" -eq 1 ] && echo symlink || echo copy)$([ "$dry" -eq 1 ] && echo ' (dry run)')"
echo "destinations:"
for d in $uniq_dests; do echo "  $base/$d"; done
echo ""

# --- conflict preflight --------------------------------------------------
shopt -s nullglob
conflicts=0
for d in $uniq_dests; do
  for src in "$source_dir"/*/; do
    name="$(basename "${src%/}")"
    [ -e "$base/$d/$name" ] && conflicts=$((conflicts + 1))
  done
done

if [ "$conflicts" -gt 0 ] && [ "$force" -eq 0 ]; then
  echo "error: $conflicts skill(s) already installed." >&2
  for d in $uniq_dests; do
    for src in "$source_dir"/*/; do
      name="$(basename "${src%/}")"
      [ -e "$base/$d/$name" ] && echo "  - $d/$name" >&2
    done
  done
  echo "re-run with --force to overwrite." >&2
  exit 1
fi

# --- install -------------------------------------------------------------
count=0
for d in $uniq_dests; do
  if [ "$dry" -eq 1 ]; then
    for src in "$source_dir"/*/; do
      echo "  would install $d/$(basename "${src%/}")"
      count=$((count + 1))
    done
    continue
  fi
  mkdir -p "$base/$d" || { echo "error: cannot create $base/$d" >&2; exit 1; }
  for src in "$source_dir"/*/; do
    src="${src%/}"
    name="$(basename "$src")"
    dest="$base/$d/$name"
    [ -e "$dest" ] || [ -L "$dest" ] && rm -rf "$dest"
    if [ "$link_mode" -eq 1 ]; then
      ln -s "$src" "$dest"
    else
      cp -R "$src" "$dest"
    fi
    count=$((count + 1))
  done
done

if [ "$dry" -eq 1 ]; then
  echo ""
  echo "dry run: $count skill installation(s) planned, nothing written."
  exit 0
fi

echo "installed $count skill copy/copies."
echo ""

# --- per-agent notes -----------------------------------------------------
case " $agents " in
  *claude*)
    echo "Claude Code: skills are picked up live. If a top-level .claude/skills/"
    echo "  did not exist at session start, run /reload-skills."
    ;;
esac
case " $agents " in
  *codex*)
    echo "Codex: scans .agents/skills upward to the repo root; restart if a new"
    echo "  skill does not appear. Disable one with [[skills.config]] in ~/.codex/config.toml."
    ;;
esac
case " $agents " in
  *cursor*)
    echo "Cursor: view installed skills in Customize > Skills. Add 'paths:' to a"
    echo "  skill's frontmatter to scope it to matching files."
    ;;
esac
case " $agents " in
  *gemini*)
    echo "Gemini CLI: /skills list shows discovered skills; .agents/skills takes"
    echo "  precedence over .gemini/skills when both exist."
    ;;
esac
echo ""
echo "verify:  scripts/install-skills.sh --list"
