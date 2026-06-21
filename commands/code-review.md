# /codex:code-review — Codex correctness/security/reliability/simplification/performance review

Adversarially review the current branch's implementation diff: a Codex debate over
correctness, security, reliability, simplification, and performance, looping until Codex
approves. Codex is the hard gate. The command never commits — you do. Mechanics live in
tested `sr_*` helpers; adjudicating findings and editing code is your (the agent's) job.

`$ARGUMENTS` (optional): `[base]` ref to diff against (default `main`).

## Phase 0 — Resolve scope

```bash
# Resolve the plugin's lib + checklists. Order: installed plugin root, project-local
# checkout, then a manual ~/.claude install. First hit wins; CKDIR is its sibling.
LIB=""; CKDIR=""
for d in "${CLAUDE_PLUGIN_ROOT:-}" ".claude/commands/codex" "${CLAUDE_HOME:-$HOME/.claude}/commands/codex"; do
  [ -n "$d" ] && [ -f "$d/codex-lib.sh" ] && { LIB="$d/codex-lib.sh"; CKDIR="$d/reference"; break; }
done
[ -n "$LIB" ] || { echo "codex-lib.sh missing — install the plugin or run install.sh"; exit 1; }
. "$LIB" || { echo "codex-lib.sh failed to source"; exit 1; }
command -v codex >/dev/null 2>&1 || { echo "codex CLI not on PATH"; exit 1; }
have="$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
sr_version_ge "${have:-0.0.0}" 0.140.0 || { echo "codex >= 0.140.0 required (have ${have:-none})"; exit 1; }

# Output mode. JSON (preferred): codex --output-schema returns schema-validated JSON,
# so structural parsing collapses to one sr_json_validate call — no fragile text grep.
# Falls back to markdown when no JSON parser (node), no schema file, or the schema is
# not strict-valid for codex (sr_schema_strict_ok) — so a bad schema degrades, not aborts.
# VFN/RFN/IDFN pick the parser so Phases 1.4/1.5 stay mode-agnostic.
SCHEMA=""; [ -n "$CKDIR" ] && SCHEMA="$(dirname "$CKDIR")/schemas/review-output.schema.json"
MODE=markdown; VFN=sr_parse_verdict; RFN=sr_round_findings; IDFN=sr_finding_ids
if sr_have_json && [ -f "$SCHEMA" ] && sr_schema_strict_ok "$SCHEMA"; then
  MODE=json; VFN=sr_json_verdict; RFN=sr_json_round_findings; IDFN=sr_json_finding_ids
fi

# args: token 1 = base ref (default main); token 2 = optional design-doc name hint
set -f; set -- ${ARGUMENTS:-}; set +f
BASE="${1:-main}"
SCOPE="$(sr_diff_scope "$BASE")" || { echo "cannot resolve scope vs '$BASE'"; exit 1; }
MB="$(printf '%s' "$SCOPE" | cut -f1)"
BRANCH="$(printf '%s' "$SCOPE" | cut -f2)"

PAYLOAD="$(sr_review_payload "$MB")"
if [ -z "$PAYLOAD" ]; then echo "Nothing to review (no changes vs $BASE)"; exit 0; fi

# design docs (spec + plan) — referenced by path for correctness/spec-compliance, not embedded
DESIGN="$(sr_design_docs "${2:-$BRANCH}")"
SPEC_DOC="$(printf '%s' "$DESIGN" | cut -f1)"
PLAN_DOC="$(printf '%s' "$DESIGN" | cut -f2)"

REPO="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
LOG="$(sr_log_path "${REPO}-$(sr_root_hash)" "$(sr_sanitize_name "$BRANCH")")"
LOG="${LOG/spec-review-/codex-review-}"   # code-review log namespace
DEP="$(sr_audit_summary)"
echo "Scope:  $BASE...HEAD ($BRANCH)"
echo "Mode:   $MODE"
echo "Log:    $LOG"
echo "Design: ${SPEC_DOC:-(none)} | ${PLAN_DOC:-(none)}"
echo "$DEP"
```

The review payload (`sr_review_payload "$MB"` — committed diff + working diff +
untracked file contents) is rebuilt at the top of each iteration so prior-iteration
edits stay in view.

## Phase 1 — Codex review + debate (hard gate, ≤ 5 iterations)

```bash
PREV_OPEN="$(sr_open_findings "$LOG")" || true   # space-separated open IDs, empty fresh
parse_fail_streak=0
```

For each iteration K (1..5):

1. Rebuild `PAYLOAD="$(sr_review_payload "$MB")"`. Build the Codex prompt in a temp file
   (never `echo` it) as **XML-tagged contract blocks** — this structure is the gate's
   quality lever, so keep the blocks and their intent:

   - `<role>` — Codex is an adversarial reviewer. Its job is to find the strongest
     reasons this change should *not* ship yet, not to validate it.
   - `<task>` — review the diff (the `$PAYLOAD`) across **five lenses**: correctness,
     security, reliability, simplification, performance. Target label: `$BASE...HEAD`.
   - `<review_criteria>` — inline the contents of ALL THREE checklists as the lens
     criteria: `$CKDIR/security-checklist.md`, `$CKDIR/reliability-checklist.md`, and
     `$CKDIR/simplification-checklist.md`. Add the `$DEP` dependency-audit line.
   - `<design_context>` — when `$SPEC_DOC`/`$PLAN_DOC` are non-empty, give those paths
     and tell Codex to read them read-only (it runs read-only in the repo) for the
     intended design, and to flag any divergence between the diff and the approved
     spec/plan as a correctness/spec-compliance finding. Reference by path; do NOT embed
     their contents.
   - `<prior_findings>` — for K>1/resume, list every prior finding by ID (incl.
     `$PREV_OPEN`) with your verdict/rebuttal, requiring Codex to mark each prior ID
     `resolved|open|superseded`.
   - `<grounding_rules>` — every finding must be defensible from the diff or a tool
     output. Do NOT invent files, lines, code paths, or runtime behavior. If a
     conclusion rests on inference, say so and keep confidence honest. (A fabricated
     finding wastes a debate round.)
   - `<finding_bar>` — report only material findings; no style/naming nits or
     speculative concerns without evidence. Each finding answers: what can go wrong, why
     this path is vulnerable, the likely impact, and the concrete fix.
   - `<calibration_rules>` — prefer one strong finding over several weak ones; do NOT
     manufacture findings to fill a lens; a clean lens gets coverage `0`. Approve only
     when no substantive finding remains.
   - `<output_contract>` — depends on `$MODE`:
     - **json** — return ONLY JSON conforming to the schema at `$SCHEMA` (no prose,
       no fences). `verdict` ∈ `APPROVED|CHANGES_REQUESTED`; `coverage` has an integer
       count for all five lenses; each `findings[]` entry has
       `id` (`R<K>F<M>`), `lens`, `file`, `line_start`, `line_end`, `severity`,
       `confidence` (0–1), `issue`, `suggestion`, and on re-review a `status`
       (`resolved|open|superseded`).
     - **markdown** — each finding headed `## Finding R<K>F<M>` with
       Lens/File/Line/Severity/Confidence/Issue/Suggestion (Line `start-end`,
       Confidence 0–1) and a `STATUS:` line on re-review; **exactly one coverage line
       per lens** — `LENS correctness: <n findings|none>` and likewise for `security`,
       `reliability`, `simplification`, `performance`; a single trailing
       `VERDICT: APPROVED|CHANGES_REQUESTED` line as the last non-empty line.
2. Run Codex under a timeout, capturing output + rc. In JSON mode the schema is enforced
   by codex and the final message (the JSON) is written with `-o`:

   ```bash
   roundfile="$(mktemp)"; errfile="$(mktemp)"
   if [ "$MODE" = json ]; then
     timeout 600 codex exec --sandbox read-only --ephemeral --output-schema "$SCHEMA" -o "$roundfile" - < "$promptfile" >/dev/null 2>"$errfile"; rc=$?
   else
     timeout 600 codex exec --sandbox read-only --ephemeral - < "$promptfile" >"$roundfile" 2>"$errfile"; rc=$?
   fi
   { echo "=== CODE REVIEW · iteration $K · $MODE · $(date +'%F %T') ==="; cat "$roundfile" "$errfile"; } >> "$LOG"
   if [ "$rc" -ne 0 ] || [ ! -s "$roundfile" ]; then
     echo "codex failed (rc=$rc) or empty output — NOT approved; see $LOG"; exit 1
   fi
   ```
3. Parse the verdict with the fail-closed counter. **JSON mode** — one structural check
   (`sr_json_validate` rejects bad JSON, a bad/missing verdict, a missing lens in
   `coverage`, a malformed or duplicate finding id, and CHANGES_REQUESTED with no
   findings):

   ```bash
   if [ "$MODE" = json ]; then
     if sr_json_validate "$roundfile"; then verdict="$(sr_json_verdict "$roundfile")"; else verdict=PARSE_FAIL; fi
     ids="$("$IDFN" "$roundfile")"
   else
     # markdown mode: the same guarantees, reconstructed from text
     verdict="$(sr_parse_verdict "$roundfile")" || true
     dups="$(sr_finding_ids "$roundfile" | sort | uniq -d)"
     ids="$(sr_finding_ids "$roundfile")"
     hdrs="$(grep -cE '^## Finding' "$roundfile")"
     goodids="$(sr_finding_ids "$roundfile" | grep -cE '^R[0-9]+F[0-9]+$')"
     lens_ok=1; for L in correctness security reliability simplification performance; do
       [ "$(grep -ciE "^LENS ${L}:" "$roundfile")" -eq 1 ] || lens_ok=0
     done
     if [ "$verdict" = "PARSE_FAIL" ] || [ -n "$dups" ] || [ "$hdrs" -ne "$goodids" ] \
        || [ "$lens_ok" -eq 0 ] || { [ "$verdict" = "CHANGES_REQUESTED" ] && [ -z "$ids" ]; }; then
       verdict=PARSE_FAIL
     fi
   fi
   # shared fail-closed handling: two parse failures in a row aborts
   if [ "$verdict" = "PARSE_FAIL" ]; then
     parse_fail_streak=$((parse_fail_streak + 1))
     if [ "$parse_fail_streak" -ge 2 ]; then
       echo "two consecutive parse failures (bad verdict / duplicate / missing IDs) — aborting; see $LOG"; exit 1
     fi
     verdict=CHANGES_REQUESTED
   else
     parse_fail_streak=0
   fi
   ```
4. **If `verdict = APPROVED`** — verify prior open IDs are accounted before accepting:

   ```bash
   # every id in $PREV_OPEN must be resolved|superseded in this round, else not approved
   accounted=1
   this_round="$("$RFN" "$roundfile")"
   for id in $PREV_OPEN; do
     st="$(printf '%s\n' "$this_round" | awk -v i="$id" '$1==i{print $2}' | tail -1)"
     case "$st" in resolved|superseded) ;; *) accounted=0 ;; esac
   done
   if [ "$accounted" -eq 1 ]; then
     # never approve over an unrun/failing build — verify before accepting (covers a
     # round-1 approval with no edits, where verify never ran)
     TESTCMD="$(sr_test_cmd)"
     if [ -n "$TESTCMD" ]; then
       eval "$TESTCMD" || { echo "tests fail at approval — NOT approved; fix and re-run; see $LOG"; exit 1; }
     else
       echo "verification: none available" >> "$LOG"
     fi
     echo "FINDING none STATUS=closed" >> "$LOG"
     # break out of the loop -> Terminate (APPROVED)
   else
     verdict=CHANGES_REQUESTED   # fall through to adjudication
   fi
   ```
5. **If not approved** — from `"$RFN" "$roundfile"`, act only on findings with
   `STATUS=open` or NEW (no `resolved|superseded`); skip closed ones. Use the finding
   bodies (markdown sections, or JSON fields via `sr_json_table`) for the issue detail.
   For each:
   - **AGREE/PARTIAL** → edit the code, then **verify** (Phase 1.5).
   - **Behavior/scope change beyond the diff's intent** → do NOT edit; halt, return the
     proposed change + finding ID for confirmation; the user re-invokes to resume.
   - **DISAGREE** → no edit; rebuttal fed into iteration K+1.
   Then write per-finding state (always, before looping):

   ```bash
   echo "FINDING $id STATUS=$status ACTION=$action" >> "$LOG"   # one line per finding this round
   ```
   Update `PREV_OPEN="$(sr_open_findings "$LOG")"` for the next iteration.
6. If K reaches 5 → stop unresolved; the latest `FINDING` block holds the open IDs.

## Phase 1.5 — Verify after edits

```bash
TESTCMD="$(sr_test_cmd)"
if [ -n "$TESTCMD" ]; then
  if ! eval "$TESTCMD"; then echo "tests failed after edits — fix or revert before the next round"; fi
else
  echo "verification: none available" >> "$LOG"
fi
```
On failure, fix or revert the offending edit before seeking a verdict; never advance a
verdict over a broken build. If no command is discoverable, the result is reported as
*review-approved, verification not run*.

## Terminate

- **APPROVED** (prior IDs accounted; verification ran or reported absent) → report a
  summary: the `$DEP` line, the per-finding table (id · lens · severity · confidence ·
  file:line · verdict · action — `sr_json_table` gives the JSON-mode rows), the
  verification result, the Codex verdict, and the log path. Relay: "Code review passed —
  proceed to finish the branch." Never commits.
- **Cap hit / failure / halted** → report the unresolved finding IDs (latest `FINDING`
  block via `sr_open_findings`) + log path; NOT approved. Re-invoking resumes.
