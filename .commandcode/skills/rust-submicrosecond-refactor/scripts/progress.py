#!/usr/bin/env python3
"""Compute progress rates between baseline / prev / current snapshots.

Usage:
  progress.py --base BASE.json --curr CURR.json [--prev PREV.json]
              [--budget-ns 300] [--append-ledger PATH] [--json]

Exit: 0 ok, 1 bad data, 2 bad args.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Optional


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def load(path: Path) -> dict[str, Any]:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        die(f"{path}: {e}")
    if not isinstance(doc, dict) or "latency_ns" not in doc:
        die(f"{path}: need object with latency_ns")
    return doc


def lat(doc: dict[str, Any], key: str) -> Optional[float]:
    v = doc.get("latency_ns", {}).get(key)
    return float(v) if v is not None else None


def pct_change(before: Optional[float], after: Optional[float]) -> Optional[float]:
    if before is None or after is None or before == 0:
        return None
    return (before - after) / before * 100.0


def speedup(before: Optional[float], after: Optional[float]) -> Optional[float]:
    if before is None or after is None or after == 0:
        return None
    return before / after


def thr_gain(before: Optional[float], after: Optional[float]) -> Optional[float]:
    if before is None or after is None or before == 0:
        return None
    return (after - before) / before * 100.0


def fmt(v: Optional[float], suffix: str = "") -> str:
    if v is None:
        return "—"
    return f"{v:.3g}{suffix}"


def row(
    name: str,
    base: Optional[float],
    prev: Optional[float],
    curr: Optional[float],
    lower_is_better: bool = True,
) -> str:
    if lower_is_better:
        step = pct_change(prev if prev is not None else base, curr)
        cum = pct_change(base, curr)
        sp_step = speedup(prev if prev is not None else base, curr)
        sp_cum = speedup(base, curr)
        step_s = (
            f"{fmt(step, '%')} ({fmt(sp_step, '×')})" if step is not None else "—"
        )
        cum_s = f"{fmt(cum, '%')} ({fmt(sp_cum, '×')})" if cum is not None else "—"
    else:
        step = thr_gain(prev if prev is not None else base, curr)
        cum = thr_gain(base, curr)
        step_s = fmt(step, "%")
        cum_s = fmt(cum, "%")
    return (
        f"| {name} | {fmt(base)} | {fmt(prev)} | {fmt(curr)} | {step_s} | {cum_s} |"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", required=True)
    ap.add_argument("--curr", required=True)
    ap.add_argument("--prev")
    ap.add_argument("--budget-ns", type=float)
    ap.add_argument("--append-ledger")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    base = load(Path(args.base))
    curr = load(Path(args.curr))
    prev = load(Path(args.prev)) if args.prev else None

    budget = args.budget_ns
    if budget is None:
        budget = curr.get("system_budget_p99_ns") or base.get("system_budget_p99_ns")

    keys = ("p50", "p99", "p99_9", "p99_99")
    metrics: dict[str, Any] = {"module": curr.get("module"), "stage": curr.get("stage")}
    for k in keys:
        b, p, c = lat(base, k), (lat(prev, k) if prev else None), lat(curr, k)
        metrics[k] = {
            "base": b,
            "prev": p,
            "curr": c,
            "step_reduction_pct": pct_change(p if p is not None else b, c),
            "cum_reduction_pct": pct_change(b, c),
            "step_speedup": speedup(p if p is not None else b, c),
            "cum_speedup": speedup(b, c),
        }

    def tail_ratio(doc: dict[str, Any]) -> Optional[float]:
        a, b = lat(doc, "p99_9"), lat(doc, "p50")
        if a is None or b is None or b == 0:
            return None
        return a / b

    metrics["tail_ratio"] = {
        "base": tail_ratio(base),
        "prev": tail_ratio(prev) if prev else None,
        "curr": tail_ratio(curr),
    }

    tb = base.get("throughput_ops_sec")
    tp = prev.get("throughput_ops_sec") if prev else None
    tc = curr.get("throughput_ops_sec")
    metrics["throughput"] = {
        "base": tb,
        "prev": tp,
        "curr": tc,
        "step_gain_pct": thr_gain(tp if tp is not None else tb, tc),
        "cum_gain_pct": thr_gain(tb, tc),
    }

    def budget_share(doc: dict[str, Any]) -> Optional[float]:
        p99 = lat(doc, "p99")
        if budget is None or p99 is None or budget == 0:
            return None
        return p99 / float(budget) * 100.0

    metrics["budget_share_pct"] = {
        "base": budget_share(base),
        "prev": budget_share(prev) if prev else None,
        "curr": budget_share(curr),
        "budget_ns": budget,
    }

    if args.json:
        print(json.dumps(metrics, indent=2))
        return

    lines = [
        f"### Progress: `{curr.get('module')}` — `{curr.get('stage')}`",
        "",
        "| Metric | Baseline | Previous | Current | Step | Cumulative |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
        row("p50 ns", lat(base, "p50"), lat(prev, "p50") if prev else None, lat(curr, "p50")),
        row("p99 ns", lat(base, "p99"), lat(prev, "p99") if prev else None, lat(curr, "p99")),
        row(
            "p99.9 ns",
            lat(base, "p99_9"),
            lat(prev, "p99_9") if prev else None,
            lat(curr, "p99_9"),
        ),
        row(
            "p99.99 ns",
            lat(base, "p99_99"),
            lat(prev, "p99_99") if prev else None,
            lat(curr, "p99_99"),
        ),
        row(
            "tail p99.9/p50",
            metrics["tail_ratio"]["base"],
            metrics["tail_ratio"]["prev"],
            metrics["tail_ratio"]["curr"],
        ),
        row(
            "throughput ops/s",
            float(tb) if tb is not None else None,
            float(tp) if tp is not None else None,
            float(tc) if tc is not None else None,
            lower_is_better=False,
        ),
        row(
            "budget share %",
            metrics["budget_share_pct"]["base"],
            metrics["budget_share_pct"]["prev"],
            metrics["budget_share_pct"]["curr"],
        ),
        "",
    ]
    text = "\n".join(lines)
    print(text)

    if args.append_ledger:
        path = Path(args.append_ledger)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            if path.stat().st_size == 0:
                f.write("# Progress Ledger\n\n")
            f.write(text + "\n")
        print(f"appended: {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
