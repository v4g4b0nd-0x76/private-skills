#!/usr/bin/env python3
"""Dual-gate A/B decision for sub-µs refactors (Mann–Whitney U + practical effect).

Sample JSON formats accepted:
  [1.0, 2.0, ...]
  {"latency_ns": […]}
  {"samples_ns": […]}

Exit: 0 both gates pass, 1 fail, 2 bad args.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


def die(msg: str, code: int = 2) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def load_samples(path: Path) -> list[float]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        die(f"cannot load samples from {path}: {e}", 1)
    if isinstance(raw, list):
        samples = raw
    elif isinstance(raw, dict):
        for key in ("latency_ns", "samples_ns", "samples"):
            if key in raw and isinstance(raw[key], list):
                samples = raw[key]
                break
        else:
            die(f"{path}: expected list or object with latency_ns/samples_ns", 1)
    else:
        die(f"{path}: unsupported JSON root", 1)
    try:
        out = [float(x) for x in samples]
    except (TypeError, ValueError) as e:
        die(f"{path}: non-numeric sample: {e}", 1)
    if len(out) < 8:
        die(f"{path}: need ≥8 samples for MWU (got {len(out)})", 1)
    return out


def median(xs: list[float]) -> float:
    s = sorted(xs)
    n = len(s)
    mid = n // 2
    if n % 2:
        return s[mid]
    return 0.5 * (s[mid - 1] + s[mid])


def percentile(xs: list[float], p: float) -> float:
    s = sorted(xs)
    if not s:
        return float("nan")
    if p <= 0:
        return s[0]
    if p >= 100:
        return s[-1]
    k = (len(s) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return s[int(k)]
    return s[f] * (c - k) + s[c] * (k - f)


def rankdata(values: list[float]) -> list[float]:
    """Average ranks for ties (1-based)."""
    indexed = sorted(enumerate(values), key=lambda t: t[1])
    ranks = [0.0] * len(values)
    i = 0
    n = len(indexed)
    while i < n:
        j = i
        while j + 1 < n and indexed[j + 1][1] == indexed[i][1]:
            j += 1
        avg = 0.5 * ((i + 1) + (j + 1))
        for k in range(i, j + 1):
            ranks[indexed[k][0]] = avg
        i = j + 1
    return ranks


def norm_sf(z: float) -> float:
    """Survival function 1-Φ(z) via erfc."""
    return 0.5 * math.erfc(z / math.sqrt(2.0))


def mann_whitney_u(x: list[float], y: list[float]) -> tuple[float, float]:
    """Two-sided MWU with normal approximation + tie correction.

    Returns (U1, p_two_sided) where U1 is the rank-sum statistic for x.
    """
    n1, n2 = len(x), len(y)
    combined = x + y
    ranks = rankdata(combined)
    r1 = sum(ranks[:n1])
    u1 = r1 - n1 * (n1 + 1) / 2.0
    u2 = n1 * n2 - u1
    u = min(u1, u2)

    # Tie correction for variance
    from collections import Counter

    counts = Counter(combined)
    tie_term = sum(t * t * t - t for t in counts.values())
    n = n1 + n2
    mean_u = n1 * n2 / 2.0
    var = (n1 * n2 / 12.0) * ((n + 1) - tie_term / (n * (n - 1))) if n > 1 else 0.0
    if var <= 0:
        return u1, 1.0
    # Continuity correction
    z = (u - mean_u + 0.5) / math.sqrt(var)
    p = min(1.0, 2.0 * norm_sf(abs(z)))
    return u1, p


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--before", required=True, help="baseline sample JSON")
    ap.add_argument("--after", required=True, help="candidate sample JSON")
    ap.add_argument("--alpha", type=float, default=0.01)
    ap.add_argument(
        "--min-median-improvement-pct",
        type=float,
        default=2.0,
        help="practical gate: median must drop by this percent (latency)",
    )
    ap.add_argument(
        "--allow-p99-only",
        action="store_true",
        help="pass practical gate if p99 drops even when median does not",
    )
    args = ap.parse_args()

    before = load_samples(Path(args.before))
    after = load_samples(Path(args.after))

    med_b, med_a = median(before), median(after)
    p99_b, p99_a = percentile(before, 99), percentile(after, 99)
    # Lower latency is better → improvement when after < before
    med_imp_pct = ((med_b - med_a) / med_b * 100.0) if med_b else 0.0
    p99_imp_pct = ((p99_b - p99_a) / p99_b * 100.0) if p99_b else 0.0

    # MWU: test whether after tends to be smaller. Use before as x, after as y;
    # we still report two-sided p, and require after median improvement separately.
    _u, p = mann_whitney_u(before, after)

    gate1 = p < args.alpha
    gate2_median = med_imp_pct >= args.min_median_improvement_pct
    gate2_p99 = args.allow_p99_only and p99_imp_pct > 0
    gate2 = gate2_median or gate2_p99

    result = {
        "n_before": len(before),
        "n_after": len(after),
        "median_before_ns": med_b,
        "median_after_ns": med_a,
        "median_improvement_pct": round(med_imp_pct, 4),
        "p99_before_ns": p99_b,
        "p99_after_ns": p99_a,
        "p99_improvement_pct": round(p99_imp_pct, 4),
        "mann_whitney_p": p,
        "alpha": args.alpha,
        "gate1_statistical": gate1,
        "gate2_practical": gate2,
        "decision": "ACCEPT" if (gate1 and gate2) else "REJECT",
    }
    print(json.dumps(result, indent=2))

    if not (gate1 and gate2):
        reasons = []
        if not gate1:
            reasons.append(f"MWU p={p:.4g} >= alpha={args.alpha}")
        if not gate2:
            reasons.append(
                f"median improvement {med_imp_pct:.3f}% < {args.min_median_improvement_pct}%"
                + ("" if args.allow_p99_only else " (and p99-only not enabled)")
            )
        print("REJECT: " + "; ".join(reasons), file=sys.stderr)
        raise SystemExit(1)
    print("ACCEPT", file=sys.stderr)


if __name__ == "__main__":
    main()
