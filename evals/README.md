# evals

Checks the `/codex:code-review` and `/codex:spec-review` commands still catch real issues.

## Run

```bash
./evals/run-evals.sh --quality --html   # everything: gate + quality + report.html
./evals/run-evals.sh                    # just the gate (fast, exit 0 = pass)
```

Open `evals/report.html` to view results. Needs `codex` ≥ 0.140.0, `node`, `jq`,
`python3`, and (for `--quality`) the `claude` CLI.

## Two evals

- **Gate** (always): builds throwaway sandboxes from `fixtures/`, runs each command's
  round-1 Codex review, and checks it catches the planted issues in `ground_truth.json`.
  Sets the exit code — drops into CI.
- **Quality** (`--quality`, slow): Codex vs Claude self-review on `quality/spec.md`,
  scored by an LLM judge. Directional comparison, not a gate. 3 trials = ~9 LLM calls
  (`QUALITY_TRIALS=1` for a cheap run).

## Add a case

Drop fixtures under `fixtures/<name>/`, then add an entry to `ground_truth.json` with the
`planted` issues. Each issue's `signal` is a regex matched against the reviewer's findings;
mark a marginal nit `"gating": false` so a probabilistic miss doesn't fail the run.

`report.html`, `results.json`, and `quality/out/` are generated and gitignored.
