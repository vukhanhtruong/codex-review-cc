#!/usr/bin/env bash
# Repeatable eval for the codex-review commands. Builds throwaway git sandboxes from
# evals/fixtures, runs the real Codex review (round 1) the way the commands do, and
# grades the findings against evals/ground_truth.json.
#
#   ./evals/run-evals.sh                # codex arm only (no Claude needed)
#   ./evals/run-evals.sh --with-claude  # also run a Claude self-review arm via `claude -p`
#
# Exit 0 iff every case caught all planted issues with the expected verdict. The Codex
# round-1 prompt below mirrors commands/code-review.md Phase 1 (contract blocks + the
# three checklists) and commands/spec-review.md section 4; keep them in sync.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$PLUGIN"
. "$PLUGIN/codex-lib.sh" || { echo "cannot source codex-lib.sh"; exit 1; }
CKDIR="$PLUGIN/reference"
SCHEMA="$PLUGIN/schemas/review-output.schema.json"
GT="$HERE/ground_truth.json"
FIX="$HERE/fixtures"

WITH_CLAUDE=0; HTML=0; QUALITY=0
for a in "$@"; do case "$a" in
  --with-claude) WITH_CLAUDE=1;; --html) HTML=1;; --quality) QUALITY=1;;
esac; done
command -v codex >/dev/null 2>&1 || { echo "codex CLI not on PATH"; exit 1; }
have="$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
sr_version_ge "${have:-0.0.0}" 0.140.0 || { echo "codex >= 0.140.0 required (have ${have:-none})"; exit 1; }

# Same mode selection the command uses: JSON only when node + a strict-valid schema exist.
MODE=markdown
if sr_have_json && [ -f "$SCHEMA" ] && sr_schema_strict_ok "$SCHEMA"; then MODE=json; fi

WORK="$(mktemp -d)"; RES="$WORK/results"; mkdir -p "$RES"
trap 'rm -rf "$WORK"' EXIT
echo "plugin: $PLUGIN"
echo "mode:   $MODE   codex: $have"
echo "work:   $WORK"

git_init() { git init -q; git config user.email eval@local; git config user.name eval; }

build_code_prompt() { # $1=base label  $2=payload  -> stdout
  local base="$1" payload="$2"
  printf '<role>\nYou are an adversarial code reviewer. Find the strongest reasons this change should NOT ship yet.\n</role>\n'
  printf '<task>\nReview the diff across five lenses: correctness, security, reliability, simplification, performance. Target: %s...HEAD.\n</task>\n' "$base"
  printf '<diff>\n%s\n</diff>\n' "$payload"
  printf '<review_criteria>\n'; cat "$CKDIR/security-checklist.md" "$CKDIR/reliability-checklist.md" "$CKDIR/simplification-checklist.md"
  printf '\n%s\n</review_criteria>\n' "$(sr_audit_summary)"
  cat <<'EOF'
<grounding_rules>Every finding must be defensible from the diff. Do NOT invent files, lines, or behavior.</grounding_rules>
<finding_bar>Report only material findings; no style nits. Each: what can go wrong, why, impact, concrete fix.</finding_bar>
<calibration_rules>Prefer one strong finding over several weak ones; a clean lens gets coverage 0.</calibration_rules>
EOF
  if [ "$MODE" = json ]; then
    echo '<output_contract>Return ONLY JSON conforming to the provided schema (no prose, no fences). verdict in APPROVED|CHANGES_REQUESTED; coverage integer per lens; findings[] id R1F<M>, lens, file, line_start, line_end, severity, confidence, issue, suggestion.</output_contract>'
  else
    echo '<output_contract>Each finding `## Finding R1F<M>` with Lens/File/Line/Severity/Confidence/Issue/Suggestion; one `LENS <name>: <n|none>` line per lens; trailing `VERDICT: APPROVED|CHANGES_REQUESTED`.</output_contract>'
  fi
}

# --- code cases ---
jq -c '.code_cases[]' "$GT" | while read -r case; do
  name=$(printf '%s' "$case" | jq -r .name)
  target=$(printf '%s' "$case" | jq -r .target)
  branch=$(printf '%s' "$case" | jq -r .branch)
  fixture=$(printf '%s' "$case" | jq -r .fixture)
  d="$WORK/$name"; mkdir -p "$d"
  ( cd "$d" && git_init \
    && cp "$FIX/$fixture/base.py" "$target" && git add -A && git commit -qm base \
    && git branch -M main && git checkout -q -b "$branch" \
    && cp "$FIX/$fixture/head.py" "$target" && git add -A && git commit -qm head )
  payload="$( cd "$d" && MB="$(sr_diff_scope main | cut -f1)" && sr_review_payload "$MB" )"
  pf="$(mktemp)"; build_code_prompt main "$payload" > "$pf"
  rf="$WORK/$name.raw"
  if [ "$MODE" = json ]; then
    ( cd "$d" && timeout 600 codex exec --sandbox read-only --ephemeral --output-schema "$SCHEMA" -o "$rf" - < "$pf" >/dev/null 2>"$WORK/$name.err" )
    if sr_json_validate "$rf"; then
      sr_json_verdict "$rf" > "$RES/$name.codex.verdict"
      node -e 'for(const f of (JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).findings||[])) console.log(f.lens,f.issue,f.suggestion)' "$rf" > "$RES/$name.codex.text"
    else echo "(invalid json)" > "$RES/$name.codex.text"; echo "?" > "$RES/$name.codex.verdict"; fi
  else
    ( cd "$d" && timeout 600 codex exec --sandbox read-only --ephemeral - < "$pf" > "$rf" 2>"$WORK/$name.err" )
    sr_parse_verdict "$rf" > "$RES/$name.codex.verdict" 2>/dev/null || echo "?" > "$RES/$name.codex.verdict"
    cp "$rf" "$RES/$name.codex.text"
  fi
  echo "  code $name -> $(cat "$RES/$name.codex.verdict")"

  if [ "$WITH_CLAUDE" = 1 ]; then
    cp="$( cd "$d" && git diff main...HEAD )"
    claude -p "You are an adversarial code reviewer. Review this diff across correctness, security, reliability, simplification, performance. List only material findings with a short reason and fix. Diff:
$cp" > "$RES/$name.claude.text" 2>/dev/null
    cp "$RES/$name.claude.text" "$RES/$name.claude.verdict" 2>/dev/null || true
    grep -qiE 'no (material )?(issue|finding)|looks good|approve' "$RES/$name.claude.text" && echo APPROVED > "$RES/$name.claude.verdict" || echo CHANGES_REQUESTED > "$RES/$name.claude.verdict"
    echo "  code $name (claude) -> $(cat "$RES/$name.claude.verdict")"
  fi
done

# --- spec cases (always markdown; spec-review has no JSON mode) ---
jq -c '.spec_cases[]' "$GT" | while read -r case; do
  name=$(printf '%s' "$case" | jq -r .name)
  doc=$(printf '%s' "$case" | jq -r .doc)
  fixture=$(printf '%s' "$case" | jq -r .fixture)
  d="$WORK/$name"; mkdir -p "$d"
  ( cd "$d" && git_init && cp -r "$FIX/$fixture/." . && git add -A && git commit -qm spec && git branch -M main )
  pf="$(mktemp)"
  { printf '<role>\nYou are an adversarial spec reviewer. Find the strongest reasons this spec is not ready to build from: gaps, ambiguities, missing acceptance criteria, untestable requirements.\n</role>\n'
    printf '<target_doc path="%s">\n' "$doc"; cat "$d/$doc"
    cat <<'EOF'
</target_doc>
<grounding_rules>Every finding must point at specific text in the doc.</grounding_rules>
<finding_bar>Only findings that would change what gets built or block implementation. No wording nits.</finding_bar>
<output_contract>Each finding `## Finding R1F<M>` with Section/Severity/Issue/Suggestion; trailing `VERDICT: APPROVED|CHANGES_REQUESTED`.</output_contract>
EOF
  } > "$pf"
  rf="$WORK/$name.raw"
  ( cd "$d" && timeout 600 codex exec --sandbox read-only --ephemeral - < "$pf" > "$rf" 2>"$WORK/$name.err" )
  sr_parse_verdict "$rf" > "$RES/$name.codex.verdict" 2>/dev/null || echo "?" > "$RES/$name.codex.verdict"
  cp "$rf" "$RES/$name.codex.text"
  echo "  spec $name -> $(cat "$RES/$name.codex.verdict")"

  if [ "$WITH_CLAUDE" = 1 ]; then
    claude -p "You are an adversarial spec reviewer. Review this design doc for gaps, ambiguities, missing acceptance criteria, untestable requirements. List only material findings. Doc:
$(cat "$d/$doc")" > "$RES/$name.claude.text" 2>/dev/null
    echo CHANGES_REQUESTED > "$RES/$name.claude.verdict"
    echo "  spec $name (claude) -> done"
  fi
done

# Optional reviewer-quality eval (slow, directional — see run-quality.sh).
QJSON=""
if [ "$QUALITY" = 1 ]; then
  bash "$HERE/run-quality.sh" || echo "quality eval had errors (see quality/out/*.err)"
  [ -f "$HERE/quality/quality-results.json" ] && QJSON="$HERE/quality/quality-results.json"
fi

LABELS=codex; [ "$WITH_CLAUDE" = 1 ] && LABELS=codex,claude
if [ "$HTML" = 1 ]; then
  python3 "$HERE/grade.py" "$RES" "$GT" --labels "$LABELS" --json "$HERE/results.json"; rc=$?
  python3 "$HERE/report.py" "$HERE/results.json" "$HERE/report.html" $QJSON && echo "HTML report: $HERE/report.html"
else
  python3 "$HERE/grade.py" "$RES" "$GT" --labels "$LABELS"; rc=$?
fi
exit $rc
