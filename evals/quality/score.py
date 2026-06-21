#!/usr/bin/env python3
"""Extract judge JSON from each trial's raw output and aggregate into quality-results.json.

    python3 score.py <out_dir> <trials> <results_path>

Each judge-trial<n>.raw is an LLM response that should be a single JSON object (we strip
code fences / surrounding prose defensively). Aggregates per-trial counts into means.
"""
import json, re, sys, pathlib, statistics as st

FIELDS = ["distinct_real_total", "both", "only_self", "only_codex",
          "self_real_total", "codex_real_total"]


def extract(raw):
    raw = raw.strip()
    raw = re.sub(r"^```(?:json)?|```$", "", raw, flags=re.M).strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", raw, re.S)   # first {...} block
        return json.loads(m.group(0)) if m else None


def main(out_dir, trials, results_path):
    od = pathlib.Path(out_dir)
    parsed = []
    for n in range(1, int(trials) + 1):
        rawf = od / f"judge-trial{n}.raw"
        if not rawf.exists():
            print(f"  trial {n}: no judge output"); continue
        obj = extract(rawf.read_text(errors="replace"))
        if not obj:
            print(f"  trial {n}: judge JSON unparseable"); continue
        obj["trial"] = n
        json.dump(obj, open(od / f"judge-trial{n}.json", "w"), indent=2)
        parsed.append(obj)

    means = {}
    if parsed:
        means = {
            "self_real": st.mean(t.get("self_real_total", 0) for t in parsed),
            "codex_real": st.mean(t.get("codex_real_total", 0) for t in parsed),
            "only_self": st.mean(t.get("only_self", 0) for t in parsed),
            "only_codex": st.mean(t.get("only_codex", 0) for t in parsed),
            "self_coverage_pct": st.mean(
                100 * t.get("self_real_total", 0) / t["distinct_real_total"]
                for t in parsed if t.get("distinct_real_total")),
        }
    json.dump({"trials": parsed, "means": means}, open(results_path, "w"), indent=2)
    print(f"  aggregated {len(parsed)} trial(s) -> {results_path}")
    if means:
        print(f"  mean real: self {means['self_real']:.1f} vs codex {means['codex_real']:.1f}"
              f" · only-codex {means['only_codex']:.1f} · only-self {means['only_self']:.1f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
