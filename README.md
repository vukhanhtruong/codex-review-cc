# codex-review-cc

A [Claude Code](https://claude.com/claude-code) plugin that summons **OpenAI Codex**
as an adversarial reviewer and debates it to convergence. Codex is the **hard gate** —
the agent (Claude) edits the code or doc; Codex decides when the work passes. Neither
command ever commits.

| Command | Reviews | Gate before |
|---|---|---|
| `/codex:spec-review` | a [superpowers](https://github.com/obra/superpowers) spec or plan doc | writing/executing the plan |
| `/codex:code-review`  | the current branch's implementation diff | finishing the branch |

## Requirements

- The [`codex` CLI](https://github.com/openai/codex) on `PATH`, **version ≥ 0.140.0**
  (both commands preflight-check this).
- Run from inside a git repo.
- Codex runs `codex exec --sandbox read-only --ephemeral` — it reads the repo but
  never writes. All edits come from Claude.

## Install

### As a plugin (recommended)

```
/plugin marketplace add vukhanhtruong/codex-review-cc
/plugin install codex@codex-review-cc
```

The plugin resolves its library and checklists from `${CLAUDE_PLUGIN_ROOT}`
automatically — nothing to copy.

### Manual (no marketplace)

```bash
git clone https://github.com/vukhanhtruong/codex-review-cc.git
cd codex-review-cc && ./install.sh
```

Copies the commands, `codex-lib.sh` + `helpers/`, and both checklists into
`${CLAUDE_HOME:-$HOME/.claude}/commands/codex`. The commands resolve the plugin root
first, then a project-local `.claude/commands/codex` checkout, then this global
install — so any closer copy overrides the global one.

## How it fits a spec → plan → code lifecycle

These commands plug in as quality gates between phases. Each runs *after* you finish a
phase and *before* you proceed — Codex must approve, or you stay in the current phase.

```
writing-plans ──► spec/plan written
     │
     ▼
┌─────────────────────────────┐
│ /codex:spec-review          │  ← gate: Codex debates the spec/plan
│   APPROVED → stamps marker  │
└─────────────────────────────┘
     │  "proceed to writing-plans" (spec) / "proceed to executing-plans" (plan)
     ▼
executing-plans ──► code written, tests pass
     │
     ▼
┌─────────────────────────────┐
│ /codex:code-review          │  ← gate: Codex debates the diff
│   APPROVED → verify ran     │
└─────────────────────────────┘
     │  "proceed to finish the branch"
     ▼
you commit + merge/PR
```

On approval each command tells you the next step. The commands never commit — you do.

## Usage

### `/codex:spec-review [spec|plan] [name-keyword]`

```bash
/codex:spec-review                      # latest spec under docs/superpowers/specs
/codex:spec-review plan                 # latest matching plan
/codex:spec-review spec evals-dataset   # spec whose name matches "evals-dataset"
```

Searches `docs/superpowers/specs/*-design.md` and `docs/superpowers/plans/`. Debate
runs in a `fork` subagent (falls back to inline if forks are unavailable) so the
back-and-forth stays out of your main conversation. Loop cap: 5 rounds. On approval it
stamps `codex-approved <date>` into the doc's frontmatter — a durable marker.

### `/codex:code-review [base]`

```bash
/codex:code-review        # diff current branch vs main
/codex:code-review dev    # diff vs an alternate base ref
```

Reviews the committed diff + working-tree diff + untracked file contents (rebuilt each
round so your edits stay in view), against the **security** and **simplification**
checklists shipped in `reference/`, plus correctness and performance lenses. Secrets
are redacted from the payload by filename and by content. When a spec/plan doc is
found for the branch, Codex reads it read-only and flags any diff-vs-design divergence.
Runs your test command at approval so it never green-lights a broken build. Loop cap: 5
rounds.

## The debate, briefly

Each round Codex emits findings (`## Finding R<K>F<M>` with Lens/File/Severity/Issue/
Suggestion) and a single `VERDICT: APPROVED | CHANGES_REQUESTED`. For every open
finding Claude renders one of:

- **AGREE / PARTIAL** → edit code/doc, then re-verify.
- **DISAGREE** → no edit; a rebuttal feeds into the next round.
- **Scope change** (removing a requirement, changing acceptance criteria, behavior
  beyond the diff's intent) → **halt**; the proposed change + finding ID come back to
  you for confirmation. Re-invoke the command to resume.

Parsing is **fail-closed**: a malformed verdict, duplicate IDs, missing finding IDs, or
a missing lens-coverage line counts as a parse failure; two in a row aborts. An
APPROVED verdict is only accepted once every prior open finding is marked
`resolved | superseded` and verification has run (or is reported absent).

State persists to a log under `/tmp` (open finding IDs, per-finding verdicts).
Re-invoking the same target **resumes** from that log — so a 5-round cap is not a dead
end.

## Layout

```
codex-review-cc/
├── .claude-plugin/
│   ├── plugin.json             # plugin manifest (name: codex → /codex:* namespace)
│   └── marketplace.json        # so `/plugin marketplace add` works on the repo
├── commands/
│   ├── code-review.md          # /codex:code-review command body
│   └── spec-review.md          # /codex:spec-review command body
├── codex-lib.sh                # barrel: sources every helper
├── helpers/                    # tested sr_* helpers (one responsibility each)
│   ├── version.sh              #   sr_version_ge
│   ├── git-scope.sh            #   sr_diff_scope
│   ├── review-payload.sh       #   sr_review_payload, sr_redact_secrets, sr_is_sensitive
│   ├── findings.sh             #   sr_parse_verdict, sr_finding_ids, sr_round/open_findings
│   ├── targets.sh              #   sr_resolve_target, sr_select_spec, sr_match_plan, sr_design_docs
│   ├── naming.sh               #   sr_sanitize_name, sr_derive_slug, sr_plan_slug
│   ├── log-identity.sh         #   sr_log_path, sr_root_hash
│   ├── dep-audit.sh            #   sr_audit_summary
│   ├── verify.sh               #   sr_test_cmd
│   └── stamp.sh                #   sr_stamp_marker
├── reference/                  # offline review checklists
│   ├── security-checklist.md
│   └── simplification-checklist.md
├── tests/                      # bash unit + install tests (npm test)
├── install.sh                  # manual (non-plugin) installer
└── LICENSE                     # MIT
```

The command `.md` files hold the orchestration logic and adjudication rules; the
deterministic mechanics live in tested `sr_*` helpers behind the `codex-lib.sh` barrel.

## Development

```bash
npm test        # runs tests/codex-lib.test.sh + tests/install.test.sh
```

## License

[MIT](LICENSE) © Khanh Truong Vu
