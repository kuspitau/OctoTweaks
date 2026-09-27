# Documentation Index

Use this file as a router. Read only what is relevant to the current task.

## Current project truth

- `CURRENT_STATE.md` — compact current implementation/validation dashboard.
- `ROADMAP.md` — future intentions, not current truth.
- `../CHANGELOG.md` — release-oriented history; do not load by default for implementation work.

## Architecture and workflow

- `../ARCHITECTURE.md` — high-level architecture.
- `architecture/module-system.md` — module contract and lifecycle.
- `architecture/hooking-policy.md` — allowed external patching strategies.
- `architecture/compatibility-policy.md` — version/structure assumptions.
- `architecture/documentation-policy.md` — project knowledge ownership and validation states.
- `architecture/delta-delivery-policy.md` — conversation-agent handoff contract.

## Target addons / systems

- `modules/pfui.md` — pfUI integration knowledge and module catalog.
- `modules/wow.md` — router for client-level WoW/OctoWoW features.
  - `modules/wow-extra-action-bars.md` — read only for `wow.extra_action_bars` work.
  - `modules/wow-warrior-assist.md` — read only for `wow.warrior_assist` work.
- `modules/aegis.md` — Aegis compatibility boundary, shared private UI seam, Market Workbench behavior and regression procedures.
- `modules/aegis-gear-search.md` — Gear Search parser/filter/scoring/preset/UI behavior and regression procedure.

Add a target document when the first module for a new addon/system is introduced. Split a feature into a companion document only when that materially reduces unrelated context for agents.

## Decisions

- `decisions/ADR-0001-external-patching.md`
- `decisions/ADR-0002-module-isolation.md`
- `decisions/ADR-0003-local-delta-workflow.md`

## Work handoff

- `work/active/` — significant work that is genuinely unfinished now. Read a note only when it matches the task.
- `work/completed/2026-09-24-aegis-gear-search.md` — retained Gear Search implementation/validation history.
- `work/completed/2026-09-21-market-workbench-stable-baseline.md` — retained Workbench baseline history.
- `work/completed/2026-09-21-extra-action-bars-stable-baseline.md` — retained Extra Action Bars history.
- `work/completed/2026-09-21-warrior-assist-stable-baseline.md` — retained Warrior Assist history.
- `work/completed/` is historical evidence, not current status, and is not part of the default reading path.
