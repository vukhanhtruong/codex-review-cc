# evals — regression harness for the codex-review commands

Proves the `/codex:code-review` and `/codex:spec-review` commands still **catch real
issues** and **engage JSON mode**, using seeded artifacts with known planted bugs as
ground truth. Run it anytime — after editing a checklist, the schema, the prompt
contract, or bumping the codex CLI.

## Run

```bash
./evals/run-evals.sh                # Codex arm only — no Claude needed
./evals/run-evals.sh --with-claude  # also run a Claude self-review arm (via `claude -p`)
```

Exit code is `0` only if every case caught all its planted issues with the expected
verdict — so it drops straight into CI or a pre-release check.

Requires: `codex` ≥ 0.140.0 on PATH, `node`, `jq`, `python3`.

## What it does

1. Builds a throwaway git sandbox per case from `fixtures/` (base commit + a feature
   branch carrying the planted code), in a `mktemp` dir that's cleaned up on exit.
2. Reproduces the command's **round-1** Codex call — same contract-block prompt and the
   same three checklists from `../reference/`. Code cases use JSON mode when the schema
   is strict-valid (`sr_schema_strict_ok`), exactly like `commands/code-review.md`
   Phase 0; spec cases use markdown (spec-review has no JSON mode).
3. Grades findings against `ground_truth.json`: each planted issue has a `signal` regex;
   it counts as caught when any finding's text matches. Reports recall + verdict per case.

It scores **round-1 detection only** — no debate loop, no code edits — so it measures the
reviewer's raw catch-rate, not the full remediation workflow.

## Reviewer-quality eval (optional, `--quality`)

A second, complementary instrument that answers a different question: *how much better is
Codex than Claude self-review?* — not "did it catch my planted bugs."

```bash
./evals/run-quality.sh                  # 3 trials, standalone
QUALITY_TRIALS=1 ./evals/run-quality.sh # cheaper
./evals/run-evals.sh --quality --html   # gate + quality, one combined report.html
```

No planted ground truth. The same spec (`quality/spec.md`) is reviewed by **Codex** and by
**Claude self-review**; a neutral **LLM judge** (`claude -p`) unions + dedups all findings
and classifies each as `both / only-codex / only-self / nit-FP`. Output: mean real issues
per reviewer + the high/med issues *only* Codex caught (the self-review's blind spots).

**This is directional, not a gate.** Per trial it costs 1 codex + 2 `claude -p` calls
(self + judge); counts wobble with model sampling and the single judge. It does **not**
set the exit code — `run-evals.sh` still passes/fails only on the signal gate. Treat the
quality numbers as a periodic capability snapshot, not CI.

## The cases (`ground_truth.json` + `fixtures/`)

| Case | Artifact | Planted ground truth |
|------|----------|----------------------|
| `tc1-user-search` | `app.py` user search | SQL injection · page-count floor-division off-by-one · sqlite connection leak |
| `tc2-hit-counter` | `counter.py` | non-atomic read-modify-write lost-update race (atomic `os.replace` is a deliberate red herring — it makes the *write* atomic but not the read-modify-write) |
| `tc3-rate-limiter` | rate-limiter spec | no over-limit response contract · ambiguous "handle bursts" · unspecified shared-store semantics |

## Editing / adding cases

- Drop a `base.py` + `head.py` (or a spec tree) under `fixtures/<name>/`.
- Add an entry to `code_cases` or `spec_cases` in `ground_truth.json` with the target
  filename/branch (or doc path) and the `planted` issues. Each `planted.signal` is a
  case-insensitive regex matched against the reviewer's finding text — keep it broad
  enough to catch a correct finding phrased differently, tight enough to not match noise.
- Mark a marginal/low-severity issue `"gating": false` if it's a nit the reviewer may
  correctly drop (LLM calibration is probabilistic near the report threshold). Non-gating
  issues are still shown in the report, but a miss does not fail the run — so the eval
  gates on real capability, not sampling luck.

## Background

This harness was built while comparing Codex review vs. Claude self-review. Both caught
every planted issue; the comparison also surfaced a real bug — the JSON `--output-schema`
mode was 400-ing because the schema left `status`/`next_steps` out of `required`
(OpenAI strict mode). That's fixed, and `sr_schema_strict_ok` now guards against the
same class of schema drift by downgrading to markdown instead of aborting the gate.
