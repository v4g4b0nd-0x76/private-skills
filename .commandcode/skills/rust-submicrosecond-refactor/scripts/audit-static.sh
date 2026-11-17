#!/usr/bin/env bash
# Static hot-path smell scan for Phase 1 Dimension A (+ light B/E keywords).
# Usage: audit-static.sh <path> [<path> ...]
# Exit: 0 if scan ran; 2 on bad args. Findings on stdout (grouped); summary on stderr.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "usage: audit-static.sh <path> [<path> ...]" >&2
  echo "  Scans Rust sources for allocation, copy, lock, and sleep smells." >&2
  exit 2
fi

for p in "$@"; do
  if [ ! -e "$p" ]; then
    echo "error: path not found: $p" >&2
    exit 2
  fi
done

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) required" >&2
  exit 1
fi

patterns=(
  'ALLOC|Vec::|String::|Box::|Arc::|Rc::|HashMap|BTreeMap|\.collect\(|\.clone\(|format!|to_owned|to_string|mem::take'
  'LOCK|std::sync::Mutex|RwLock|mpsc::|parking_lot'
  'SLEEP|thread::sleep|Instant::now|std::time::Instant'
  'SERDE|serde_json|bincode|prost::|toml::|serde_yaml'
  'DYN|\bdyn\s+|Box<dyn'
)

total=0
for label_pat in "${patterns[@]}"; do
  label="${label_pat%%|*}"
  pat="${label_pat#*|}"
  echo "## $label"
  # Prefer content matches; empty is fine.
  if out="$(rg -n --glob '*.rs' -e "$pat" "$@" 2>/dev/null || true)"; then
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
      total=$((total + count))
    else
      echo "(none)"
    fi
  fi
  echo ""
done

echo "summary: $total matching lines (not all are hot-path bugs — triage against call graph)" >&2
