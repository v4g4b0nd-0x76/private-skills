#!/usr/bin/env python3
"""Write / validate .bench-history baseline JSON snapshots.

Usage:
  persist_baseline.py validate <file.json>
  persist_baseline.py write --out PATH --module NAME --stage STAGE [options]

Exit codes: 0 ok, 1 validation/write failure, 2 bad args.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REQUIRED_TOP = (
    "module",
    "stage",
    "timestamp_utc",
    "latency_ns",
)
REQUIRED_LAT = ("p50", "p99")


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as e:
        die(f"cannot read {path}: {e}")
    except json.JSONDecodeError as e:
        die(f"invalid JSON in {path}: {e}")


def validate(doc: Any, path: str = "<doc>") -> list[str]:
    errs: list[str] = []
    if not isinstance(doc, dict):
        return [f"{path}: expected object"]
    for k in REQUIRED_TOP:
        if k not in doc:
            errs.append(f"missing '{k}'")
    lat = doc.get("latency_ns")
    if isinstance(lat, dict):
        for k in REQUIRED_LAT:
            if k not in lat:
                errs.append(f"missing latency_ns.{k}")
            elif not isinstance(lat[k], (int, float)):
                errs.append(f"latency_ns.{k} must be number")
    elif "latency_ns" in doc:
        errs.append("latency_ns must be object")
    return errs


def git_sha(cwd: Path) -> str:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=cwd, stderr=subprocess.DEVNULL, text=True
        )
        return out.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def rustc_version() -> str:
    try:
        out = subprocess.check_output(["rustc", "--version"], text=True)
        return out.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def cmd_validate(args: argparse.Namespace) -> None:
    doc = load_json(Path(args.file))
    errs = validate(doc, args.file)
    if errs:
        for e in errs:
            print(f"error: {e}", file=sys.stderr)
        raise SystemExit(1)
    print("OK")


def cmd_write(args: argparse.Namespace) -> None:
    out = Path(args.out)
    lat: dict[str, float] = {}
    if args.latency_json:
        raw = load_json(Path(args.latency_json))
        if isinstance(raw, dict) and "latency_ns" in raw:
            lat = {k: float(v) for k, v in raw["latency_ns"].items()}
        elif isinstance(raw, dict):
            lat = {k: float(v) for k, v in raw.items()}
        else:
            die("--latency-json must be an object of percentiles or {latency_ns:…}")
    for key, val in (
        ("p50", args.p50),
        ("p99", args.p99),
        ("p99_9", args.p99_9),
        ("p99_99", args.p99_99),
        ("conditional_tail_excess_p99_ns", args.cte_p99),
    ):
        if val is not None:
            lat[key] = float(val)
    if "p50" not in lat or "p99" not in lat:
        die("need at least p50 and p99 (flags or --latency-json)")

    env: dict[str, Any] = {}
    if args.env_json:
        env = load_json(Path(args.env_json))
        if not isinstance(env, dict):
            die("--env-json must be an object")
    if args.from_env:
        env.setdefault("rustc_version", rustc_version())

    doc: dict[str, Any] = {
        "module": args.module,
        "stage": args.stage,
        "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_commit": args.git_commit or git_sha(out.parent if out.parent.exists() else Path(".")),
        "environment": env,
        "workload": {
            "mode": args.mode,
            "target_rate_ops_sec": args.rate,
            "warmup_ops": args.warmup,
            "measured_ops": args.measured,
        },
        "latency_ns": lat,
        "throughput_ops_sec": args.throughput,
        "system_budget_p99_ns": args.budget_p99,
    }
    if args.counters_json:
        doc["hardware_counters"] = load_json(Path(args.counters_json))
    if args.memory_json:
        doc["memory_profile"] = load_json(Path(args.memory_json))

    errs = validate(doc)
    if errs:
        die("; ".join(errs))

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and not args.force:
        die(f"{out} exists (pass --force to overwrite)")
    out.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(str(out))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("validate", help="validate a baseline JSON file")
    v.add_argument("file")
    v.set_defaults(func=cmd_validate)

    w = sub.add_parser("write", help="write a baseline/step snapshot")
    w.add_argument("--out", required=True)
    w.add_argument("--module", required=True)
    w.add_argument("--stage", required=True)
    w.add_argument("--latency-json")
    w.add_argument("--p50", type=float)
    w.add_argument("--p99", type=float)
    w.add_argument("--p99-9", dest="p99_9", type=float)
    w.add_argument("--p99-99", dest="p99_99", type=float)
    w.add_argument("--cte-p99", type=float)
    w.add_argument("--throughput", type=float)
    w.add_argument("--budget-p99", type=float, default=300.0)
    w.add_argument("--mode", default="open_loop")
    w.add_argument("--rate", type=float)
    w.add_argument("--warmup", type=int)
    w.add_argument("--measured", type=int)
    w.add_argument("--env-json")
    w.add_argument("--from-env", action="store_true")
    w.add_argument("--counters-json")
    w.add_argument("--memory-json")
    w.add_argument("--git-commit")
    w.add_argument("--force", action="store_true")
    w.set_defaults(func=cmd_write)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
