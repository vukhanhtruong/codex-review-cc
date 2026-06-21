# Reliability Review Criteria

Reliability/operational lens for `/codex:code-review` — actionable criteria, not prose.
This lens covers the *operational* failure modes that correctness and security miss:
what happens under retries, concurrency, partial failure, version skew, and degraded
dependencies. **Scope to the change's surface:** apply only categories the code can
actually hit (skip migration items on a pure CLI string helper; treat a state mutation
or external call as in-scope). Assume the happy path works — hunt the unhappy ones.

## Idempotency & retries
- Operations that can be retried (network calls, queue handlers, webhooks) must be safe
  to run twice — dedupe by key, upsert, or guard with an idempotency token.
- A retry after a partial success must not double-charge, double-send, or duplicate rows.
- Backoff is bounded; retries have a cap and don't amplify load on a struggling dependency.

## Partial failure & rollback
- Multi-step writes (DB + external API, multiple tables) define what happens when step N
  fails after step N-1 committed — transaction, saga/compensation, or documented
  inconsistency window.
- Failure paths leave state recoverable, not wedged; no "half-applied" record with no path forward.
- Rollback/undo is actually reachable for the change's worst case; cleanup runs on the error path.

## Concurrency & ordering
- Shared state accessed concurrently is guarded (lock, atomic op, compare-and-swap, queue).
- No check-then-act races (TOCTOU) on files, balances, counters, or status fields.
- Code does not assume message/event ordering the transport doesn't guarantee; out-of-order
  and duplicate delivery are handled.
- Re-entrancy: a handler invoked again before the first completes does not corrupt state.

## Empty / null / boundary state
- Empty collection, first-run, zero-rows, and null-dependency cases behave (no crash, no
  misleading default).
- Timeouts set on every external call; a slow/unavailable dependency degrades gracefully
  rather than hanging the caller.
- Resource bounds: pagination/streaming for large sets; no unbounded in-memory accumulation.

## Version skew & migration
- Schema/contract changes are forward- and backward-compatible across a rolling deploy
  (old code reads new data, new code reads old) — or an explicit migration order is stated.
- Data migrations are reversible or have a tested recovery; no destructive, irreversible
  step without a guard.
- API/event payload changes are additive, or versioned; consumers won't break on new fields.

## Observability & recovery
- Failures are detectable: errors logged with enough context to diagnose; no silently
  swallowed exceptions on a critical path.
- Key state transitions and external-call outcomes are observable (log/metric) so an
  on-call can tell what happened.
- Alerting/monitoring hooks exist for the failure modes that matter, where applicable.

## Reliability Review Checklist
- [ ] Retryable operations are idempotent; no double-effect on retry.
- [ ] Multi-step writes define partial-failure behavior; state stays recoverable.
- [ ] Shared/concurrent state guarded; no TOCTOU; ordering assumptions justified.
- [ ] Empty/null/first-run/boundary cases handled; external calls have timeouts.
- [ ] Schema/contract changes survive a rolling deploy; migrations reversible or recoverable.
- [ ] Failures are logged with context and detectable; no silent swallow on critical paths.
- [ ] Resource use bounded (memory, recursion, query size); degraded dependency tolerated.

## Severity guidance
critical/high = data loss, corruption, wedged state, or an outage reachable in the
change's deployment context → fix before approval.
medium = fix this cycle. low = track. Likelihood × blast radius decides severity.
