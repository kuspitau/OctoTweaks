# Documentation Index

Use this file as a router. Read only what is relevant to the current task.

## Current project truth

- `CURRENT_STATE.md` — what is implemented and validated now.
- `ROADMAP.md` — future intentions, not current truth.
- `../CHANGELOG.md` — release-oriented history.

## Architecture and workflow

- `../ARCHITECTURE.md` — high-level architecture.
- `architecture/module-system.md` — module contract and lifecycle.
- `architecture/hooking-policy.md` — allowed external patching strategies.
- `architecture/compatibility-policy.md` — version/structure assumptions.
- `architecture/documentation-policy.md` — how agents maintain project knowledge.
- `architecture/delta-delivery-policy.md` — how conversation agents hand changes to the user's evolving local repository.

## Target addons / systems

- `modules/pfui.md` — pfUI integration knowledge and module catalog.
- `modules/wow.md` — WoW/OctoWoW client-level features, including virtual extra action bars.
- `modules/aegis.md` — Aegis Exchange 1.53.16 audit, adapter contract, Market Workbench prototype, and runtime test procedure.

Add a target document when the first module for a new addon/system is introduced.

## Decisions

- `decisions/ADR-0001-external-patching.md`
- `decisions/ADR-0002-module-isolation.md`
- `decisions/ADR-0003-local-delta-workflow.md`

## Work handoff

- `work/active/` — significant unfinished tasks only.
- `work/active/extra-action-bars.md` — first runtime-validation handoff for `wow.extra_action_bars`.
- `work/active/market-workbench.md` — Aegis adapter/Market Workbench prototype runtime-validation handoff.
- `work/completed/` — finalized handoff notes worth retaining.
