# Documentation Policy for Agents

## Objective

The repository must remain resumable by a new agent without requiring a full-codebase read or reconstruction from conversation history.

Documentation is therefore part of the implementation, not optional commentary.

The user's local repository may temporarily be ahead of GitHub while conversation-agent deltas are being tested. Documentation shipped inside each delta must describe the resulting local state, not merely the last remote commit.

## Sources of truth

### `AGENTS.md`

Stable working protocol. Keep it short enough to read at the start of most tasks. Do not store project history here.

### `docs/CURRENT_STATE.md`

Only facts that are true in the repository after the delta is applied: implemented modules, validation state, current limitations, current environment/workflow assumptions.

Never put speculative future work here except a narrowly stated pending validation directly attached to current code.

### `ARCHITECTURE.md` and `docs/architecture/`

Current design, engineering rules, and stable local workflow.

### `docs/modules/<target>.md`

Reusable knowledge about a target addon/system and the OctoTweaks modules that integrate with it.

Record version-scoped discoveries that future agents should not have to rediscover from third-party source.

### `docs/ROADMAP.md`

Future ideas and planned work. Nothing in this file implies implementation.

### `CHANGELOG.md`

Release/user-visible history, not internal task narration.

### `docs/decisions/ADR-*.md`

Durable decisions whose rationale should survive later refactors.

### `docs/work/active/`

Significant unfinished work handoff only. Not every small task needs a work note.

### `docs/work/completed/`

Completed work notes worth retaining because they preserve important implementation/validation context not already captured elsewhere.

## Update decision table

When a change affects:

- current implementation/status -> update `CURRENT_STATE.md`;
- target-addon knowledge/module behavior -> update the target module doc;
- architecture/workflow -> update architecture docs;
- durable design choice -> add/update an ADR;
- significant unfinished work -> update an active work note;
- future intention only -> update `ROADMAP.md`;
- release-facing change -> update `CHANGELOG.md`.

Do not update every file mechanically.

## State and validation model

Keep implementation state, validation evidence, and work lifecycle separate. Do not use `PENDING` as a permanent catch-all.

### Work lifecycle

- `ACTIVE` — a concrete issue/change is currently open and needs more implementation or validation. It should normally have a note in `docs/work/active/` when the handoff is significant.
- `STABLE` — the current intended baseline is implemented, static checks pass where applicable, and the user has accepted the relevant real-client behavior. A stable module may still have documented limitations or future enhancements.
- `BLOCKED` — use only when progress is genuinely prevented by an external dependency/evidence gap. State the blocker exactly.

### Validation evidence

Use explicit labels when detailed status is needed:

- `IMPLEMENTED` — code exists; says nothing by itself about runtime correctness.
- `STATIC VALIDATION: PASS` — repository/source/tool checks actually ran successfully.
- `IN-GAME VALIDATION: PENDING` — changed runtime behavior has not yet been exercised.
- `IN-GAME VALIDATION: PARTIAL` — meaningful runtime evidence exists but a release-relevant changed branch remains untested.
- `IN-GAME VALIDATION: PASS` — the user has exercised/accepted the relevant current behavior. Acceptance may be based on normal sustained use; do not invent per-branch observations the user did not report.
- `SOURCE-AUDITED` — third-party source/API structure was inspected. This is compatibility evidence, not a runtime PASS.

A narrow known bug does not automatically downgrade every related module. Mark the affected work item/module `ACTIVE`, while keeping unrelated validated integration layers `STABLE`.

Never convert `PENDING` to `PASS` from code inspection alone. A conversation agent must not claim that `addon_update.bat` or an in-game test passed unless the user supplied that result or the execution environment genuinely performed that exact check.

### Validation debt lifecycle

When the user accepts a feature/module as working:

1. update `CURRENT_STATE.md` to `STABLE`/runtime PASS;
2. update the authoritative module doc with concise runtime evidence;
3. remove obsolete `PENDING` language tied to that behavior;
4. move/delete any corresponding `docs/work/active/` note; retain it under `work/completed/` only if it preserves useful implementation/validation history;
5. leave future enhancements in `ROADMAP.md`, not as fake validation debt.

A later change should reopen validation only for behavior plausibly affected by that change. Unrelated changes do not reset a stable module to `PENDING`.

### Procedure ownership

`CURRENT_STATE.md` is a dashboard, not a test manual. Keep short current summaries and the exact remaining active validation there. Reusable regression procedures belong in `docs/modules/<target>.md` or `tests/README.md`; temporary staged checklists belong in an active work note only while the work is active.

## Avoid duplication

Prefer one authoritative description plus links/references over copying the same long explanation into several files.

Source comments should explain local code invariants, not duplicate architecture documents.

## Handoff quality

An active work note should allow a new agent to answer, without conversation history:

- What was the goal?
- What is already done?
- What remains?
- What files matter?
- What assumptions/discoveries matter?
- What approaches were rejected and why?
- What validation has actually run?
- What runtime/manual validation remains?

The corresponding `delta_changes.zip` must include every documentation update required to make the post-extraction local repository self-consistent.
