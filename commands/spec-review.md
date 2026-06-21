# /codex:spec-review — Adversarial Codex review of a spec or plan

Summon OpenAI Codex to adversarially review the latest (or named) superpowers spec
or plan, then debate until Codex approves. Codex is the hard gate.

`$ARGUMENTS` (optional): a target word `spec` or `plan`, and/or a name keyword.
Examples: `/codex:spec-review`, `/codex:spec-review plan`, `/codex:spec-review spec evals-dataset`.

## 1. Preflight

```bash
# Resolve the plugin's lib. Order: installed plugin root, project-local checkout,
# then a manual ~/.claude install. First hit wins.
LIB=""
for d in "${CLAUDE_PLUGIN_ROOT:-}" ".claude/commands/codex" "${CLAUDE_HOME:-$HOME/.claude}/commands/codex"; do
  [ -n "$d" ] && [ -f "$d/codex-lib.sh" ] && { LIB="$d/codex-lib.sh"; break; }
done
[ -n "$LIB" ] || { echo "codex-lib.sh missing — install the plugin or run install.sh"; exit 1; }
. "$LIB" || { echo "codex-lib.sh failed to source"; exit 1; }
command -v codex >/dev/null 2>&1 || { echo "codex CLI not on PATH"; exit 1; }
have="$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
sr_version_ge "${have:-0.0.0}" 0.140.0 || { echo "codex >= 0.140.0 required (have ${have:-none})"; exit 1; }
```

## 2. Resolve the target

```bash
SPECS=docs/superpowers/specs
PLANS=docs/superpowers/plans
FORCE=""; NAME=""
set -f                       # no glob expansion of $ARGUMENTS tokens
for tok in $ARGUMENTS; do
  case "$tok" in
    spec|plan) FORCE="$tok" ;;
    *) NAME="${NAME:+$NAME }$tok" ;;
  esac
done
set +f

OUT="$(sr_resolve_target "$SPECS" "$PLANS" "$FORCE" "$NAME")"; rc=$?
case "$rc" in
  3) echo "Ambiguous match — be more specific:"; echo "$OUT"; exit 1 ;;
  4) echo "No spec found (searched $SPECS/*-design.md):"; ls "$SPECS"/*-design.md 2>/dev/null; exit 1 ;;
  5) echo "Forced 'plan' but no single matching plan exists"; exit 1 ;;
esac
TARGET="$(printf '%s' "$OUT" | cut -f1)"
DOC="$(printf '%s' "$OUT" | cut -f2)"
SPEC_RO="$(printf '%s' "$OUT" | cut -f3)"   # set only when TARGET=plan

REPO="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
SAFE="$(sr_sanitize_name "${NAME:-$(sr_derive_slug "${DOC##*/}")}")"
LOG="$(sr_log_path "$REPO" "$SAFE")"
echo "Target: $TARGET — $DOC"
echo "Log:    $LOG"
```

## 3. Fork the reviewer-driver

Dispatch a fork subagent so the debate churn stays out of this conversation:

> Use the Agent tool with `subagent_type: "fork"`. Pass it: `TARGET`, `DOC`,
> `SPEC_RO` (if plan), `LOG`, `CAP=5`, and the loop instructions in section 4.
> The fork reconstructs design rationale from the spec/plan/`docs/adr/*`/handoff
> docs — never assume the conversation holds it.

If `subagent_type: "fork"` is unavailable, run section 4 inline in this session
(findings then enter the main context — accepted fallback). Durable outputs are
identical either way.

## 4. Debate loop (runs in the fork) — `CAP=5`

On entry, recover any still-open findings from a prior run (resume):

```bash
PREV_OPEN="$(sr_open_findings "$LOG")" || true   # space-separated IDs, empty on fresh run
[ -n "$SPEC_RO" ] && SPEC_SHA="$({ sha256sum "$SPEC_RO" 2>/dev/null || shasum -a 256 "$SPEC_RO"; } | awk '{print $1}')"
parse_fail_streak=0                       # consecutive PARSE_FAIL counter (fail closed at 2)
```

For each round N (1..CAP):

1. Build the prompt in a temp file (never `echo` the prompt):
   - context block (CLAUDE.md, `.claude/rules/*`, relevant arch docs),
   - the target doc; for a plan review also the **read-only** `SPEC_RO`,
   - for N>1 or a resumed run: prior findings by ID (including `PREV_OPEN`) + your
     per-finding verdicts/rebuttals, asking Codex to mark each prior ID
     `resolved | open | superseded`.
   - Require the finding format `## Finding <ID>` with Section/Severity/Issue/
     Suggestion, and a single trailing `VERDICT:` line.
2. Run Codex read-only, capturing stdout/stderr to real files and checking its exit
   code explicitly (do not mask it through a pipe):

   ```bash
   roundfile="$(mktemp)"; errfile="$(mktemp)"
   codex exec --sandbox read-only --ephemeral - < "$promptfile" >"$roundfile" 2>"$errfile"; rc=$?
   { echo "=== ${TARGET^^} REVIEW · round $N · $(date +'%F %T') ==="; cat "$roundfile" "$errfile"; } >> "$LOG"
   if [ "$rc" -ne 0 ] || [ ! -s "$roundfile" ]; then
     echo "codex failed (rc=$rc) or empty output — NOT approved; see $LOG"; exit 1
   fi
   ```
3. Parse the verdict from `roundfile`:

   ```bash
   verdict="$(sr_parse_verdict "$roundfile")" || true   # PARSE_FAIL returns rc1 by design; handled below
   if [ "$verdict" = "PARSE_FAIL" ]; then
     parse_fail_streak=$((parse_fail_streak + 1))
     if [ "$parse_fail_streak" -ge 2 ]; then
       echo "two consecutive PARSE_FAILs — aborting (fail closed); see $LOG"; exit 1
     fi
     verdict=CHANGES_REQUESTED   # treat this round as changes-requested, retry next round
   else
     parse_fail_streak=0
   fi
   ```
4. **If `verdict = APPROVED`** → record an empty open set, then break (so a later
   resume never re-feeds stale IDs from an earlier round's `OPEN:` line):

   ```bash
   echo "OPEN:" >> "$LOG"
   break
   ```
5. Otherwise read findings with `sr_finding_ids "$roundfile"`; surface any finding
   whose body is unparseable verbatim. For each open finding, render a verdict and
   act within the **edit boundaries**:
   - **AGREE / PARTIAL** → edit `DOC` (auto-apply only wording clarifications, added
     detail, fixed placeholders, resolved ambiguity).
   - **Scope change** (removing a requirement, changing acceptance/success criteria)
     → do NOT edit. Halt the loop early and return the proposed change + the open
     finding ID for user confirmation; the user re-invokes `/codex:spec-review` to resume.
   - **DISAGREE** → no edit; record a rebuttal to feed into round N+1.
6. During a **plan** review, write only `DOC`; re-check the spec hash and abort if it
   changed:

   ```bash
   if [ -n "$SPEC_RO" ] && [ "$({ sha256sum "$SPEC_RO" 2>/dev/null || shasum -a 256 "$SPEC_RO"; } | awk '{print $1}')" != "$SPEC_SHA" ]; then
     echo "read-only spec changed during plan review — aborting"; exit 1
   fi
   ```
7. Record the IDs still open after this round's debate — **always, before looping**:

   ```bash
   echo "OPEN: $open_ids" >> "$LOG"   # space-separated unresolved IDs (empty if none)
   ```
8. If N reaches CAP → stop unresolved; the last `OPEN:` line holds the remaining IDs;
   partial edits remain on disk.

## 5. Terminate

- **APPROVED** → stamp the durable marker and report:

  ```bash
  sr_stamp_marker "$DOC" "codex-approved $(date +%F)"
  ```
  Return a summary table (finding · severity · verdict · action) + the log path.
  Relay: spec → "proceed to writing-plans"; plan → "proceed to executing-plans".
  The command never commits — the user commits the doc.
- **Cap hit / failure** → return the unresolved finding IDs (also in the log's last
  `OPEN:` line) + log path; report NOT approved. Re-invoking on the same target
  resumes (reads `OPEN:` via `sr_open_findings`, appends to the same log).
