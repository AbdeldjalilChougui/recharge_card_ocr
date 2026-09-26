#!/usr/bin/env python3
"""Summarise a results JSON written by run_on_device.dart.

Usage:
    python3 report.py build/benchmark/results.json [--zone code]
                      [--variant NAME] [--failures 20] [--compare other.json]

Metrics, per variant and per zone (default: every zone that has labels):
  * exact-match accuracy, overall and per condition tag (and per font);
  * character error rate: Levenshtein distance between the predicted and
    the true code, divided by the true length (no prediction counts as all
    characters deleted);
  * dangerous misses: a wrong or missing-but-returned code that was NOT
    flagged needsReview (the app would have used a wrong code silently);
  * false alarms: a correct code that was flagged needsReview;
  * median and p95 latency of one full read (all zones) on the device.

Only the Python standard library is needed.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict


def levenshtein(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def percentile(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    k = (len(s) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


class Tally:
    def __init__(self) -> None:
        self.n = 0
        self.correct = 0
        self.edits = 0
        self.chars = 0
        self.dangerous = 0
        self.false_alarm = 0
        self.flagged = 0
        self.no_code = 0

    def add(self, truth: str, pred: str | None, review: bool) -> None:
        self.n += 1
        ok = pred == truth
        self.correct += ok
        self.edits += levenshtein(pred or "", truth)
        self.chars += len(truth)
        self.flagged += review
        self.no_code += pred is None
        if pred is not None and not ok and not review:
            self.dangerous += 1
        if ok and review:
            self.false_alarm += 1

    def pct(self, k: int, d: int | None = None) -> str:
        d = self.n if d is None else d
        return f"{100 * k / d:.1f}%" if d else "-"

    def row(self, name: str) -> str:
        cer = self.edits / self.chars if self.chars else 0
        return (
            f"| {name} | {self.n} | {self.pct(self.correct)} | {cer:.3f} | "
            f"{self.dangerous} ({self.pct(self.dangerous)}) | "
            f"{self.false_alarm} ({self.pct(self.false_alarm, self.correct)}) | "
            f"{self.pct(self.flagged)} |"
        )


HEADER = (
    "| group | n | exact match | CER | dangerous misses | false alarms (of correct) | flagged for review |\n"
    "|---|---:|---:|---:|---:|---:|---:|"
)


def truth_for(label: dict, zone: str) -> str | None:
    return label.get(zone)


def summarise(variant: dict, labels: dict, zone: str, failures: int) -> tuple[str, dict]:
    by_file = {e["file"]: e for e in labels["images"]}
    overall = Tally()
    per_cond: dict[str, Tally] = defaultdict(Tally)
    per_font: dict[str, Tally] = defaultdict(Tally)
    latencies = []
    fails = []
    errors = 0
    for r in variant["results"]:
        lab = by_file[r["file"]]
        truth = truth_for(lab, zone)
        if truth is None:
            continue
        latencies.append(r["ms"])
        if "error" in r:
            errors += 1
            pred, review, z = None, True, {}
        else:
            z = r["zones"].get(zone, {})
            pred, review = z.get("code"), z.get("needsReview", True)
        overall.add(truth, pred, review)
        for c in lab.get("conditions", []):
            per_cond[c].add(truth, pred, review)
        if lab.get("font"):
            per_font[lab["font"]].add(truth, pred, review)
        if pred != truth:
            fails.append((r["file"], truth, pred, review, z.get("reasons"), z.get("confidence"), z.get("ocrText")))

    out = [f"### Zone `{zone}` ({variant['name']})", ""]
    out.append(HEADER)
    out.append(overall.row("**all**"))
    for c in sorted(per_cond, key=lambda k: (k != "clean", k)):
        out.append(per_cond[c].row(c))
    out.append("")
    if len(per_font) > 1:
        out.append("By font:\n")
        out.append(HEADER)
        for f in sorted(per_font):
            out.append(per_font[f].row(f))
        out.append("")
    out.append(
        f"Latency per photo (all zones): median {statistics.median(latencies):.0f} ms, "
        f"p95 {percentile(latencies, 0.95):.0f} ms, n={len(latencies)}"
        + (f"; {errors} errors" if errors else "")
    )
    out.append("")
    if failures and fails:
        out.append(f"Failures (first {min(failures, len(fails))} of {len(fails)}):\n")
        out.append("| file | truth | predicted | review | reasons | conf | OCR text |")
        out.append("|---|---|---|---|---|---:|---|")
        for f in fails[:failures]:
            ocr = (f[6] or "").replace("\n", " / ").replace("|", "\\|")
            out.append(f"| {f[0]} | {f[1]} | {f[2]} | {f[3]} | {','.join(f[4] or [])} | {f[5]} | {ocr[:80]} |")
        out.append("")
    stats = {
        "n": overall.n,
        "accuracy": overall.correct / overall.n if overall.n else 0,
        "cer": overall.edits / overall.chars if overall.chars else 0,
        "dangerous": overall.dangerous,
        "false_alarms": overall.false_alarm,
        "median_ms": statistics.median(latencies) if latencies else None,
        "p95_ms": percentile(latencies, 0.95),
    }
    return "\n".join(out), stats


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("results")
    ap.add_argument("--zone", action="append", help="zone(s) to report (default: all labelled)")
    ap.add_argument("--variant", help="only this variant")
    ap.add_argument("--failures", type=int, default=0, help="list up to N failures per zone")
    ap.add_argument("--json", action="store_true", help="print one summary JSON line per variant/zone")
    args = ap.parse_args(argv)

    data = json.load(open(args.results, encoding="utf-8"))
    labels = data["labels"]
    zones = args.zone or [z for z in labels["spec"] if any(z in e for e in labels["images"])]
    src = labels.get("source", "?")
    print(f"# recharge_card_ocr benchmark\n")
    print(f"Source: {src} images ({len(labels['images'])}), device: {data.get('device', {}).get('os', '?')}, "
          f"run: {data.get('createdAt', '?')}\n")
    for v in data["variants"]:
        if args.variant and v["name"] != args.variant:
            continue
        print(f"## Variant `{v['name']}`\n")
        if v.get("config") and len(v["config"]) > 1:
            print(f"Config: `{json.dumps(v['config'])}`\n")
        for zone in zones:
            text, stats = summarise(v, labels, zone, args.failures)
            if args.json:
                print(json.dumps({"variant": v["name"], "zone": zone, **stats}))
            else:
                print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
