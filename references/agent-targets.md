# Agent Target Matrix

Load this when installing skills into an agent, debugging "the skill doesn't appear", or adding a new target.

Verified against vendor documentation on **2026-11-14**. These paths change; re-verify before trusting them (see [Re-verifying](#re-verifying)).

## Where each agent looks

| Agent | Project path | User path | Notes |
|---|---|---|---|
| Command Code | `.commandcode/skills/` | `~/.commandcode/skills/` | this repo's native format |
| Codex CLI | `.agents/skills/` | `~/.agents/skills/` | also `.codex/skills/`; scans **upward to the repo root** |
| Cursor | `.agents/skills/` or `.cursor/skills/` | `~/.agents/skills/` or `~/.cursor/skills/` | also reads `.claude/skills/` and `.codex/skills/` |
| Gemini CLI | `.agents/skills/` or `.gemini/skills/` | `~/.agents/skills/` or `~/.gemini/skills/` | `.agents` wins over `.gemini` in the same tier |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` | also `.claude/commands/*.md` (legacy) |
| Codex admin | — | `/etc/codex/skills/` | machine-wide |

## The important consequence

**`.agents/skills/` is read natively by Codex, Cursor, and Gemini.** One copy covers three agents. Claude Code is the only one that needs its own path, and Cursor will read `.claude/skills/` too if you prefer one directory everywhere.

So the cheapest portable layout is:

```
project/
├── .agents/skills/<name>/SKILL.md     # Codex + Cursor + Gemini
└── .claude/skills/<name>/SKILL.md     # Claude Code
```

Run `scripts/install-skills.sh <project> --agent agents,claude` to produce exactly that.

## Per-agent detail

### Codex CLI

- Scans `.agents/skills` in the current directory, each parent up to the repo root, and `$REPO_ROOT/.agents/skills`.
- Two skills with the same `name` are **not merged** — both appear in the selector.
- Follows **symlinks** (useful for `--link` installs).
- Restart Codex if a new skill does not appear.
- Disable one without deleting: `[[skills.config]]` with `path` or `name` and `enabled = false` in `~/.codex/config.toml`.
- The initial skill list is capped (~2% of context, or 8000 chars); with many skills Codex **shortens descriptions first**, which is why the first sentence must carry the trigger.
- Skill-level UI/policy metadata goes in `agents/openai.yaml`.

### Cursor

- Reads `.agents/skills/`, `.cursor/skills/`, `~/.agents/skills/`, `~/.cursor/skills/`.
- Compatibility: also `.claude/skills/`, `.codex/skills/`, and their user-level equivalents.
- Walks the skills root **recursively** — category subfolders are fine; identity comes from the folder containing `SKILL.md`.
- A nested `.cursor/skills/` anywhere in the repo is picked up and auto-scoped to that subtree.
- Extra frontmatter Cursor understands: `paths` (glob scoping), `disable-model-invocation`, `icon`, `color`, `metadata`. `globs` is a legacy fallback for `paths`.
- Rules (`.cursor/rules/*.mdc`) are a *separate* mechanism for always-on guidance — do not confuse them with skills.

### Gemini CLI

- User: `~/.gemini/skills/` or `~/.agents/skills/`. Workspace: `.gemini/skills/` or `.agents/skills/`.
- Precedence within a tier: `.agents/skills/` beats `.gemini/skills/`.
- Activation requires **user consent** per skill — expect a confirmation prompt on first use.
- `/skills list`, `/skills enable|disable`, `/skills link <path>` manage them in-session; `gemini skills install` from the terminal.

### Claude Code

- Personal `~/.claude/skills/`, project `.claude/skills/`, nested `.claude/skills/` below the cwd (loaded when Claude touches files there).
- Symlinked skill folders are supported and de-duplicated by target.
- Picks up changes **live** within a session; if you create a new top-level skills dir mid-session, run `/reload-skills`.
- **Frontmatter restriction:** outside Claude Code (claude.ai upload, Skills API), only spec fields are allowed — `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. A field like `argument-hint` is a hard error on upload. Keep extra fields out of skills you intend to publish.
- Invocation control: `disable-model-invocation: true` for side-effectful skills; `user-invocable: false` for background knowledge.

## Portability rules for this repo

1. **Only use spec frontmatter** in `SKILL.md`: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. Anything else is ignored by some agents and rejected by others.
2. Put agent-specific metadata in `metadata:` (a string map) or in the agent's own file (`agents/openai.yaml`), never as a top-level field.
3. `name` must equal the directory name — every agent requires it.
4. Prefer `.agents/skills` for the shared copy.
5. Keep descriptions front-loaded: Codex truncates them first when the list is large.

## Failure modes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Skill missing in Codex | not under `.agents/skills` in a scanned ancestor | install with `--agent codex`, restart |
| Skill missing in Claude Code | created after session start | `/reload-skills` |
| Skill missing in Gemini | consent declined, or disabled | `/skills list`, `/skills enable <name>` |
| Skill loads for the wrong tasks | description too broad / no negative trigger | fix description, run `trigger-eval.sh` |
| Claude upload fails with "Unexpected key(s)" | non-spec frontmatter | strip to the six spec fields |
| Two skills with the same name | both appear (Codex) or one wins (Gemini tier rules) | rename one |

## Re-verifying

Vendor paths drift. When a skill does not appear:

1. Read the agent's own docs, not a blog post:
   - Codex: `developers.openai.com/codex/skills`
   - Cursor: `cursor.com/docs/skills`
   - Gemini: `geminicli.com/docs/cli/skills`
   - Claude Code: `code.claude.com/docs/en/skills`
2. Confirm the directory the agent reports in its own UI (`/skills`, Customize → Skills).
3. Update this file and the matrix in `install-skills.sh --list` in the same change.
