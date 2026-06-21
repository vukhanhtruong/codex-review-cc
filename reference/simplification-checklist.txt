# Simplification Review Criteria

Simplification lens for `/codex:code-review` — actionable rules, not prose. Goal: easier to
read/understand/modify — not fewer lines. Test: "Would a new team member understand
this faster than the original?"

## Principles
- **Preserve behavior exactly** — identical inputs, outputs, side effects, error
  handling; existing tests pass unmodified.
- **Follow project conventions** — match neighboring code + CLAUDE.md for imports,
  declarations, naming, error handling — not external preferences.
- **Clarity over cleverness** — explicit beats compact when compact needs a mental
  pause; name intermediate steps; avoid dense ternary chains.
- **Maintain balance** — don't inline helpers that name a concept, don't merge
  unrelated logic, preserve abstractions for testability; never optimize for line count.
- **Scope to what changed** — simplify recently modified code; no drive-by refactors;
  keep diffs focused and reviewable.

## Understand before cutting (Chesterton's Fence)
- Identify the code's responsibility; map callers and callees.
- Note edge cases, error paths, and the tests defining expected behavior before changing.

## Structural targets (with thresholds)
- 3+ nesting levels → extract guard clauses / early returns.
- Functions over ~50 lines doing several things → split by responsibility.
- Nested ternaries → if/else chains or lookup objects.
- Boolean flag parameters → options object.
- Repeated conditionals → named predicate functions.

## Naming
- Replace generic names (`data`, `result`, `temp`, `val`) with descriptive ones.
- Full words unless the abbreviation is universal (`id`, `url`, `api`).
- Name functions for actual behavior, not assumed intent.
- Delete comments explaining *what*; keep comments explaining *why*.

## Redundancy & dead code
- Extract duplicated logic (5+ lines) into shared helpers; reuse existing ones.
- Remove dead code, unreachable branches, unused variables/imports.
- Inline wrappers that add no value; drop redundant type assertions.

## Apply incrementally
- One simplification at a time; run tests after each; commit each separately.
- Separate refactoring from feature/bug-fix changes.

## Avoid flagging when
- The code is already clear; performance-critical paths where the explicit form is
  intentional; a module slated for rewrite.

## Verification Checklist
- [ ] All tests pass without modification.
- [ ] Build succeeds with no new warnings.
- [ ] Code follows project conventions.
- [ ] Each change is reviewable and incremental; no unrelated changes mixed in.
- [ ] No error handling removed or weakened.
- [ ] No dead code or unused imports remain.
- [ ] Net improvement is clear to a reviewer.
