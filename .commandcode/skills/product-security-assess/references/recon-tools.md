# Recon tools

Load before `ensure-tools.sh` / `recon.sh`.

## Required binaries

| Tool | Role in this skill |
|------|--------------------|
| `ffuf` | Path/content discovery on allowlisted base URLs |
| `nmap` | Port/service inventory on allowlisted hosts/IPs |
| `nuclei` | Template hits tagged `discovery,tech,config,exposure` only; severity medium+ |

These feed **`assets.json`** for Bright entrypoint registration. They are not a license
to run exploit payloads, custom XSS/SQLi, or off-allowlist hosts.

("ninja" in operator shorthand maps here to **nuclei** + **nmap**; this skill does
not ship the Ninja build system.)

## Bootstrap

```bash
bash $SKILL_DIR/scripts/ensure-tools.sh --check
# if missing:
bash $SKILL_DIR/scripts/ensure-tools.sh --install
export PATH="$(bash $SKILL_DIR/scripts/ensure-tools.sh --print-path):$PATH"
```

`--install` uses `go install` for ffuf/nuclei (needs Go) and the OS package manager
for nmap. Binaries land in `$PSA_TOOLS_DIR` or `~/.local/share/product-security-assess/bin`.

## Recon rules (enforced)

1. ROE `authorized: true`
2. Every probed host must be in / under `targets.json`
3. ffuf uses the skill wordlist (`assets/wordlist-paths.txt`) — do not swap in
   attack payload lists
4. nuclei runs with fixed tags + medium/high/critical — Info/noise stays out of
   ranked findings via `report.sh`
5. Off-allowlist URLs in tool output are dropped and noted in `assets.json`

## When to skip

```bash
bash $SKILL_DIR/scripts/recon.sh <run-id> --skip-nuclei
bash $SKILL_DIR/scripts/recon.sh <run-id> --skip-ffuf --skip-nmap   # harness / offline
```
