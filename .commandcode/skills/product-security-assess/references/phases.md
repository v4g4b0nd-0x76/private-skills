# Phase contracts

Load when advancing black, gray, or white.

## Phase order

| From | To | Gate |
|------|----|------|
| (none) | init | `--init --target` |
| init | tools | `ensure-tools.sh --check` (or `--install`) |
| tools | recon | ROE `authorized: true`; writes `assets.json` |
| init/recon | black | ROE `authorized: true`; prefer `assets.json` from recon |
| black | gray | `credentials.ref` set; black artifacts exist |
| gray | white | `code-root` exists; gray artifacts exist |
| white | report | whitebox `surface.md` exists |
| report | check | `report.md` exists |

Tools/recon are prerequisites for a real black box run; harness fixtures may
seed `assets.json` without calling nmap/ffuf.

`phase.json` shape:

```json
{
  "phase": "init|black|gray|white|report",
  "armed_destructive": false,
  "updated": "ISO-8601"
}
```

## Black artifacts

- `assets.json` — `{ "hosts": [...], "urls": [...], "notes": "..." }`
- `scans/black.json` — Bright scan ids / test tags used / authObjectId null
- `findings/black.jsonl` — lines: `{"severity","class","endpoint","title","evidence","phase":"black"}`

## Gray artifacts

- Same as black with `scans/gray.json`, `findings/gray.jsonl`, non-null `authObjectId` in the scan file.

## White artifacts

- `whitebox/surface.md` — entry points, identity sources, object refs, privileged actions
- `whitebox/gaps.md` — missing ownership checks, IDOR-prone refs, priv boundaries (candidates only)
- Optional: `whitebox/suite/` when `--suite` (local harness; not aimed at live domain)

## Advancing without Bright (harness fixtures)

In CI without Bright MCP, the agent may write minimal valid JSON artifacts that
record `status: "fixture"` and empty findings. Production runs must replace those
with real Bright ids before marking findings `confirmed`.
