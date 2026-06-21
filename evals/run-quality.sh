#!/usr/bin/env bash
# Judge-based reviewer-QUALITY eval: Codex peer-review vs Claude self-review on a fixed
# spec, scored by a neutral LLM judge. This is a DIRECTIONAL capability comparison, not a
# pass/fail gate — counts wobble with model sampling and the single judge per trial.
#
#   ./evals/run-quality.sh            # 3 trials (default)
#   QUALITY_TRIALS=1 ./evals/run-quality.sh
#
# Cost: per trial = 1 codex + 1 claude (self) + 1 claude (judge) call. 3 trials = 9 calls.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
QD="$HERE/quality"; OUT="$QD/out"; mkdir -p "$OUT"
SPEC="$QD/spec.md"; CRIT="$QD/review-criteria.txt"
TRIALS="${QUALITY_TRIALS:-3}"
command -v codex  >/dev/null 2>&1 || { echo "codex CLI not on PATH"; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "claude CLI required (self-review + judge)"; exit 1; }

review_prompt() { cat "$CRIT"; printf '\n=================== SPEC UNDER REVIEW ===================\n\n'; cat "$SPEC"; }

judge_prompt() { # $1 self review file  $2 codex review file
  cat <<'EOF'
You are a neutral, rigorous judge comparing two adversarial reviews of the SAME design spec.
Review A = a self-review (Claude). Review B = a peer-review (Codex). Both use the same finding format.

Build the UNION of DISTINCT, REAL issues across both reviews. Merge duplicates/rephrasings into one
issue. EXCLUDE nits, style, false positives, and anything not defensible against the spec. For each
distinct real issue decide who found it: both, only A (self), or only B (codex).

Output ONLY a single JSON object — no prose, no code fences:
{
  "distinct_real_total": <int>,
  "both": <int>,
  "only_self": <int>,
  "only_codex": <int>,
  "self_real_total": <int>,        // both + only_self
  "codex_real_total": <int>,       // both + only_codex
  "self_dropped_nits_fp": <int>,   // A findings judged nit/FP/dupe
  "codex_dropped_nits_fp": <int>,  // B findings judged nit/FP/dupe
  "only_codex_high_med": [ "<short phrase (sev)>", ... ],  // high/med issues only Codex caught
  "only_self_items": [ "<short phrase>", ... ]             // issues only the self-review caught
}

--- REVIEW A (self) ---
EOF
  cat "$1"
  printf '\n--- REVIEW B (codex) ---\n'
  cat "$2"
}

echo "quality eval: $TRIALS trial(s) on $(basename "$SPEC")"
for n in $(seq 1 "$TRIALS"); do
  echo "  trial $n: codex…"
  pf="$(mktemp)"; review_prompt > "$pf"
  ( cd "$(mktemp -d)" && timeout 600 codex exec --sandbox read-only --skip-git-repo-check --ephemeral - ) \
    < "$pf" > "$OUT/codex-trial$n.txt" 2>"$OUT/codex-trial$n.err"
  echo "  trial $n: self (claude)…"
  claude -p "$(review_prompt)" > "$OUT/self-trial$n.txt" 2>"$OUT/self-trial$n.err"
  echo "  trial $n: judge…"
  jf="$(mktemp)"; judge_prompt "$OUT/self-trial$n.txt" "$OUT/codex-trial$n.txt" > "$jf"
  claude -p "$(cat "$jf")" > "$OUT/judge-trial$n.raw" 2>"$OUT/judge-trial$n.err"
  cf=$(grep -c '^## Finding' "$OUT/codex-trial$n.txt" 2>/dev/null || echo 0)
  sf=$(grep -c '^## Finding' "$OUT/self-trial$n.txt" 2>/dev/null || echo 0)
  echo "  trial $n: codex=$cf self=$sf findings"
done

python3 "$QD/score.py" "$OUT" "$TRIALS" "$QD/quality-results.json"
echo "quality-results: $QD/quality-results.json"
