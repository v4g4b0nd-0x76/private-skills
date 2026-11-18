#!/usr/bin/env bash
# Allowlisted asset recon → assets.json (feeds Bright entrypoints).
# Uses ffuf + nmap (+ optional nuclei discovery tags). Never expands past targets.json.
# Exit: 0 ok, 1 validation, 2 safety refusal
# Usage: recon.sh <run-id> [--skip-nuclei] [--skip-ffuf] [--skip-nmap]
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="${1:-}"
shift || true

[ -n "$run_id" ] || { echo "usage: recon.sh <run-id> [--skip-nuclei] [--skip-ffuf] [--skip-nmap]" >&2; exit 1; }

skip_nuclei=0
skip_ffuf=0
skip_nmap=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-nuclei) skip_nuclei=1; shift ;;
    --skip-ffuf) skip_ffuf=1; shift ;;
    --skip-nmap) skip_nmap=1; shift ;;
    -h|--help)
      echo "usage: recon.sh <run-id> [--skip-nuclei] [--skip-ffuf] [--skip-nmap]" >&2
      exit 1
      ;;
    *) echo "error: unexpected '$1'" >&2; exit 1 ;;
  esac
done

root=".product-security/$run_id"
roe="$root/roe.md"
targets_file="$root/targets.json"
refuse() { echo "REFUSED: $*" >&2; exit 2; }
die() { echo "error: $*" >&2; exit 1; }

[ -d "$root" ] || die "missing $root — run assess.sh --init first"
[ -f "$targets_file" ] || die "missing $targets_file"
grep -qE '^authorized:[[:space:]]*true[[:space:]]*$' "$roe" 2>/dev/null \
  || refuse "ROE authorized: true required before recon"

# Ensure needed tools on PATH (check only — install is explicit via ensure-tools.sh)
bin_dir="$(bash "$skill_dir/scripts/ensure-tools.sh" --print-path)"
export PATH="$bin_dir:$PATH"
need_check=0
[ "$skip_nmap" -eq 0 ] && need_check=1
[ "$skip_ffuf" -eq 0 ] && need_check=1
[ "$skip_nuclei" -eq 0 ] && need_check=1
if [ "$need_check" -eq 1 ]; then
  bash "$skill_dir/scripts/ensure-tools.sh" --check >/dev/null
else
  echo "note: all recon tools skipped — writing allowlist-only assets.json"
fi

mkdir -p "$root/recon"
wordlist="$skill_dir/assets/wordlist-paths.txt"
[ -f "$wordlist" ] || die "missing wordlist $wordlist"

python3 - "$root" "$targets_file" "$wordlist" "$skip_nmap" "$skip_ffuf" "$skip_nuclei" "$skill_dir" <<'PY'
import json, os, re, subprocess, sys, ipaddress, shutil
from datetime import datetime, timezone
from urllib.parse import urlparse

root, targets_path, wordlist, skip_nmap, skip_ffuf, skip_nuclei, skill_dir = sys.argv[1:8]
skip_nmap, skip_ffuf, skip_nuclei = map(int, (skip_nmap, skip_ffuf, skip_nuclei))
hosts = json.load(open(targets_path)).get("hosts") or []
if not hosts:
    print("REFUSED: empty allowlist", file=sys.stderr)
    raise SystemExit(2)

allow = {h.lower().rstrip(".") for h in hosts}
recon_dir = os.path.join(root, "recon")
urls = set()
ports = []
notes = []
nuclei_hits = []

def is_ip(h):
    try:
        ipaddress.ip_address(h)
        return True
    except ValueError:
        return False

def host_allowed(h):
    h = (h or "").lower().rstrip(".")
    if h in allow:
        return True
    # subdomain of an allowlisted DNS name
    for a in allow:
        if not is_ip(a) and (h == a or h.endswith("." + a)):
            return True
    return False

def base_urls_for(h):
    if is_ip(h):
        return [f"http://{h}", f"https://{h}"]
    return [f"https://{h}", f"http://{h}"]

# --- nmap ---
if not skip_nmap:
    nmap = shutil.which("nmap")
    if not nmap:
        print("error: nmap missing", file=sys.stderr)
        raise SystemExit(1)
    for h in hosts:
        out = os.path.join(recon_dir, f"nmap-{re.sub(r'[^A-Za-z0-9._-]', '_', h)}.xml")
        cmd = [nmap, "-Pn", "-sV", "--top-ports", "100", "-oX", out, h]
        print("+", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=False)
        if not os.path.isfile(out):
            notes.append(f"nmap produced no xml for {h}")
            continue
        text = open(out, errors="ignore").read()
        for port, state, svc in re.findall(
            r'<port protocol="tcp" portid="(\d+)".*?<state state="([^"]+)"[^/]*/>.*?(?:<service name="([^"]*)")?',
            text,
            re.S,
        ):
            if state != "open":
                continue
            ports.append({"host": h, "port": int(port), "service": svc or ""})
            if (svc or "") in ("http", "https", "http-proxy", "ssl/http", "http-alt"):
                scheme = "https" if "ssl" in (svc or "") or port in ("443", "8443") else "http"
                if port in ("80", "443"):
                    urls.add(f"{scheme}://{h}")
                else:
                    urls.add(f"{scheme}://{h}:{port}")
else:
    notes.append("nmap skipped")

# seed URLs from hosts even without nmap
for h in hosts:
    for u in base_urls_for(h):
        urls.add(u)

# --- ffuf ---
ffuf_results = []
if not skip_ffuf:
    ffuf = shutil.which("ffuf")
    if not ffuf:
        print("error: ffuf missing", file=sys.stderr)
        raise SystemExit(1)
    for h in hosts:
        for base in base_urls_for(h):
            out = os.path.join(recon_dir, f"ffuf-{re.sub(r'[^A-Za-z0-9._-]', '_', base)}.json")
            # FUZZ as path segment; only follow responses that stay on allowlisted host
            cmd = [
                ffuf, "-u", f"{base}/FUZZ", "-w", wordlist,
                "-mc", "200,201,204,301,302,307,401,403",
                "-t", "10", "-timeout", "5",
                "-of", "json", "-o", out,
                "-s",
            ]
            print("+", " ".join(cmd), flush=True)
            subprocess.run(cmd, check=False)
            if not os.path.isfile(out):
                continue
            try:
                data = json.load(open(out))
            except Exception:
                continue
            for r in data.get("results") or []:
                url = r.get("url") or ""
                host = urlparse(url).hostname or ""
                if not host_allowed(host):
                    notes.append(f"ffuf dropped off-allowlist url: {url}")
                    continue
                urls.add(url.split("?")[0])
                ffuf_results.append({"url": url, "status": r.get("status"), "host": host})
else:
    notes.append("ffuf skipped")

# --- nuclei (discovery/tech only; not a free-form exploit run) ---
if not skip_nuclei:
    nuclei = shutil.which("nuclei")
    if nuclei:
        out = os.path.join(recon_dir, "nuclei.jsonl")
        targets_txt = os.path.join(recon_dir, "nuclei-targets.txt")
        with open(targets_txt, "w") as fh:
            for u in sorted(urls):
                host = urlparse(u).hostname or ""
                if host_allowed(host):
                    fh.write(u + "\n")
        cmd = [
            nuclei, "-l", targets_txt, "-jsonl", "-o", out,
            "-tags", "discovery,tech,config,exposure",
            "-severity", "medium,high,critical",
            "-rate-limit", "50", "-c", "10",
            "-silent",
        ]
        print("+", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=False)
        if os.path.isfile(out):
            with open(out) as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    matched = obj.get("matched-at") or obj.get("host") or ""
                    host = urlparse(matched).hostname if "://" in matched else matched
                    host = (host or "").split(":")[0]
                    if not host_allowed(host):
                        notes.append(f"nuclei dropped off-allowlist: {matched}")
                        continue
                    nuclei_hits.append({
                        "template": obj.get("template-id") or obj.get("templateID"),
                        "name": (obj.get("info") or {}).get("name"),
                        "severity": (obj.get("info") or {}).get("severity"),
                        "matched": matched,
                    })
                    if matched.startswith("http"):
                        urls.add(matched.split("?")[0])
    else:
        notes.append("nuclei missing; skipped")
else:
    notes.append("nuclei skipped")

# Final allowlist filter on URLs
safe_urls = []
for u in sorted(urls):
    host = urlparse(u).hostname or ""
    if host_allowed(host):
        safe_urls.append(u)
    else:
        notes.append(f"dropped off-allowlist url: {u}")

assets = {
    "hosts": hosts,
    "urls": safe_urls,
    "ports": ports,
    "ffuf": ffuf_results[:500],
    "nuclei_discovery": nuclei_hits[:200],
    "notes": notes,
    "recon_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "tools": {"ffuf": not skip_ffuf, "nmap": not skip_nmap, "nuclei": not skip_nuclei},
}
out_path = os.path.join(root, "assets.json")
json.dump(assets, open(out_path, "w"), indent=2)
open(out_path, "a").write("\n")
print(f"wrote {out_path} ({len(safe_urls)} urls, {len(ports)} open ports)")
PY
