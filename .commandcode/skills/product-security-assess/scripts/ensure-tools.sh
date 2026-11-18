#!/usr/bin/env bash
# Check or install recon tools used by product-security-assess.
# Tools: ffuf (content discovery), nmap (ports/services), nuclei (exposure templates).
# Exit: 0 ok, 1 missing/failed install, 2 bad usage
# Usage: ensure-tools.sh --check | --install | --print-path
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="${PSA_TOOLS_DIR:-$HOME/.local/share/product-security-assess/bin}"
action="${1:-}"

usage() {
  cat >&2 <<'EOF'
usage: ensure-tools.sh --check | --install | --print-path

Required tools (allowlisted recon only — not exploit frameworks):
  ffuf    web content / API path discovery
  nmap    host/port/service inventory
  nuclei  template-based exposure discovery (non-destructive tags by default)

Installs to: $PSA_TOOLS_DIR or ~/.local/share/product-security-assess/bin
EOF
  exit 2
}

[ -n "$action" ] || usage

# Ordered NAME|go_package_or_empty
TOOLS=(
  "ffuf|github.com/ffuf/ffuf/v2@latest"
  "nmap|"
  "nuclei|github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
)

have() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  [ -x "$bin_dir/$name" ]
}

resolve() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  if [ -x "$bin_dir/$name" ]; then
    echo "$bin_dir/$name"
    return 0
  fi
  return 1
}

export_path_hint() {
  echo "export PATH=\"$bin_dir:\$PATH\""
}

case "$action" in
  --print-path)
    echo "$bin_dir"
    exit 0
    ;;

  --check)
    missing=0
    echo "== product-security-assess tools =="
    echo "bin_dir: $bin_dir"
    for entry in "${TOOLS[@]}"; do
      name="${entry%%|*}"
      if path="$(resolve "$name")"; then
        ver="$("$path" --version 2>/dev/null | head -1 || "$path" -V 2>/dev/null | head -1 || echo "ok")"
        echo "  OK  $name  ($path)  $ver"
      else
        echo "  MISSING  $name" >&2
        missing=$((missing + 1))
      fi
    done
    if [ "$missing" -gt 0 ]; then
      echo "" >&2
      echo "error: $missing tool(s) missing — run: ensure-tools.sh --install" >&2
      export_path_hint >&2
      exit 1
    fi
    echo "all tools present"
    export_path_hint
    exit 0
    ;;

  --install)
    mkdir -p "$bin_dir"
    # Prefer user-local bin on PATH for this shell and children
    export PATH="$bin_dir:$PATH"

    need_go=0
    for entry in "${TOOLS[@]}"; do
      name="${entry%%|*}"
      pkg="${entry#*|}"
      if have "$name"; then
        echo "have $name"
        continue
      fi
      if [ -n "$pkg" ]; then
        need_go=1
      fi
    done

    if [ "$need_go" -eq 1 ] && ! command -v go >/dev/null 2>&1; then
      echo "error: go is required to install ffuf/nuclei (install go, then re-run)" >&2
      exit 1
    fi

    for entry in "${TOOLS[@]}"; do
      name="${entry%%|*}"
      pkg="${entry#*|}"
      if have "$name"; then
        continue
      fi
      case "$name" in
        nmap)
          echo "installing nmap via package manager..."
          if command -v apt-get >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
              sudo apt-get update -qq && sudo apt-get install -y -qq nmap
            else
              apt-get update -qq && apt-get install -y -qq nmap
            fi
          elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y nmap
          elif command -v brew >/dev/null 2>&1; then
            brew install nmap
          else
            echo "error: cannot install nmap automatically — install it and re-run --check" >&2
            exit 1
          fi
          ;;
        *)
          echo "installing $name with go install $pkg ..."
          GOBIN="$bin_dir" go install "$pkg"
          ;;
      esac
    done

    # nuclei template update is best-effort (network)
    if path="$(resolve nuclei)"; then
      echo "updating nuclei templates (best-effort)..."
      "$path" -update-templates >/dev/null 2>&1 || true
    fi

    bash "$skill_dir/scripts/ensure-tools.sh" --check
    ;;

  -h|--help) usage ;;
  *) echo "error: unknown action '$action'" >&2; usage ;;
esac
