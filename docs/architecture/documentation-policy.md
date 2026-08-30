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

## Validation wording

Use explicit labels such as:

- `IMPLEMENTED`
- `STATIC VALIDATION: PASS`
- `IN-GAME VALIDATION: PENDING`

Never convert `PENDING` to `PASS` based on code inspection alone.

A conversation agent must not claim that `addon_update.bat` or an in-game test passed unless the user actually ran it and supplied the result, or the execution environment genuinely performed that exact check.

When an agent cannot perform an in-game test, document the exact manual steps needed.

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
