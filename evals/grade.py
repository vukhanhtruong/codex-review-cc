#!/usr/bin/env python3
"""Grade codex-review eval results against ground_truth.json.

Reads, per case + arm, two files produced by run-evals.sh in the results dir:
  <name>.<arm>.verdict  -> APPROVED | CHANGES_REQUESTED
  <name>.<arm>.text     -> reviewer finding text

A planted issue counts as CAUGHT when its `signal` regex matches the finding text.
Exit 0 only if every case (every arm) caught all planted issues AND matched
expect_verdict. With --json, also dumps structured results for report.py.
"""
import json, re, sys, pathlib, argparse


def collect(results_dir, gt_path, labels):
    gt = json.load(open(gt_path))
    rd = pathlib.Path(results_dir)
    cases = [("code", c) for c in gt.get("code_cases", [])] + \
            [("spec", c) for c in gt.get("spec_cases", [])]
    data, overall = [], True
    for arm in labels:
        for typ, c in cases:
            name = c["name"]
            raw = _read(rd / f"{name}.{arm}.text")
            verdict = _read(rd / f"{name}.{arm}.verdict").strip() or "?"
            planted = []
            for p in c["planted"]:
                gating = p.get("gating", True)
                hit = bool(raw) and re.search(p["signal"], raw, re.I) is not None
                planted.append({"id": p["id"], "desc": p["desc"],
                                "caught": hit, "gating": gating})
                if gating:
                    overall = overall and hit
            exp = c.get("expect_verdict")
            vok = (verdict == exp) if exp else True
            overall = overall and vok and bool(raw)
            n = sum(1 for x in planted if x["caught"] and x["gating"])
            tot = sum(1 for x in planted if x["gating"])
            data.append({"arm": arm, "name": name, "type": typ, "verdict": verdict,
                         "expect": exp, "verdict_ok": vok, "missing_output": not raw,
                         "recall": [n, tot], "planted": planted, "findings": raw})
    return data, overall


def _read(p):
    try:
        return p.read_text(errors="replace")
    except FileNotFoundError:
        return ""


def print_table(data):
    for arm in dict.fromkeys(d["arm"] for d in data):
        print(f"\n=== {arm} arm — catch-rate vs planted ground truth ===")
        for d in [x for x in data if x["arm"] == arm]:
            if d["missing_output"]:
                print(f"\n  {d['name']}: NO OUTPUT"); continue
            vbad = "" if d["verdict_ok"] else f" != {d['expect']} ✗"
            n, tot = d["recall"]
            print(f"\n  {d['name']}  [verdict {d['verdict']}{vbad}]  recall {n}/{tot}")
            for p in d["planted"]:
                mark = "✓" if p["caught"] else ("✗" if p["gating"] else "·")
                tag = "" if p["gating"] else "  (non-gating)"
                print(f"    [{mark}] {p['id']} {p['desc']}{tag}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("results"); ap.add_argument("ground_truth")
    ap.add_argument("--labels", default="codex")
    ap.add_argument("--json")
    a = ap.parse_args()
    data, ok = collect(a.results, a.ground_truth, a.labels.split(","))
    print_table(data)
    if a.json:
        json.dump(data, open(a.json, "w"), indent=2)
    print("\n" + ("PASS — all planted issues caught, verdicts as expected" if ok
                  else "FAIL — see ✗ above"))
    sys.exit(0 if ok else 1)
