# Market Workbench — active handoff

## Goal

Build an OctoTweaks orchestration layer over Aegis: Exchange that keeps **Target Item** separate from **Reference Listing**, automatically searches comparable items, and supports very short selling workflows without replacing Aegis' mature AH backend.

## Stable baseline — phase 1

The following workflow is runtime-confirmed on the user's Aegis Exchange **1.20.2** setup:

- Target Item capture and retention;
- corrected OctoWoW item metadata;
- Similar Search from the custom Aegis AH UI;
- page polling/result collection;
- grouped parent rows plus individual listings;
- hover/tooltips after the vanilla full-link fix;
- independent Reference Listing selection through `SET`;
- Match / Flat / Percent Suggested Price;
- direct multi-stack `POST` through Aegis `sell.StartPosting`.

This is the regression baseline. Do not rewrite the scanner, grouped-result semantics, tooltip path, or posting backend merely to integrate the UI.

## Current implemented slice — Aegis-hosted Workbench

This delta adds:

- `modules/aegis/UIAdapter.lua`, a dedicated private-presentation boundary inside `aegis.integration`;
- exact UI source pinning to Aegis 1.20.2 upstream commit `70f648492607ca1aec6c3df2da42deed21d09c9d`;
- structural probes for `ui.BuildWindow`, `ui.OpenWindow`, `ui.SelectSubTab`, and the post-build `ui.subtabs` / `ui.panels` / `ui.content` host;
- `aegis.market_workbench_ui`, isolated from the already validated backend Workbench module;
- a seventh `Workbench` Aegis sub-tab and dedicated Aegis panel, added externally without modifying Aegis files;
- reuse/reparenting of the existing Workbench presentation rather than a second Buy/Sell implementation;
- temporary Aegis host-height acquisition while the 870x500 Workbench is selected, with restoration before normal Aegis tabs repaint and protection against undoing a user resize;
- `/otmarket` routing into the integrated tab while Aegis is open, with standalone fallback outside Aegis;
- integrated close/toggle behavior that returns to Aegis Buy instead of leaving an empty panel;
- UI diagnostics appended to `/otmarket status`.

The Market Workbench v1 pricing milestone is now a runtime-confirmed baseline: plain-right-click Target → automatic Similar Search → automatic first-priced Reference → persisted undercut preset → Suggested Price, with SellValue-backed vendor comparison when available. The iteration-5 vendor/gain correction is confirmed working in game. `POST + NEXT` is **not** included in v1; safer auto-pricing safeguards are the preferred next milestone before accelerating posting.

## Important audit discoveries

Authoritative reusable detail is in `docs/modules/aegis.md`. The key conclusions are:

- The exact Aegis 1.20.2 source is identifiable upstream at commit `70f64849...`; its `.toc` reports version 1.20.2.
- `BuildWindow()` creates static initial tabs, but after construction the runtime dispatcher uses mutable `ui.subtabs` and `ui.panels` tables.
- `ui.SelectSubTab(name)` iterates those tables dynamically, so an externally appended key is shown/hidden/tinted by Aegis' own dispatcher.
- `ui.RefreshCurrentTab()` has no fallback error for unknown keys; it simply skips Aegis-specific refresh work. This makes an extension panel substantially less fragile than replacing Aegis Buy/Sell.
- The Workbench itself does not need direct Aegis UI access. Every new private reference lives in `UIAdapter.lua`.
- Presentation internals remain low-stability/private despite this useful seam. The new integration is therefore exact-version-gated to 1.20.2. Backend Workbench support remains separate and can continue on structurally compatible versions.
- Aegis 1.20.2 already contains a Post/Skip bag queue, but this slice does not bind to that private workflow. It is design evidence for later `POST + NEXT`, not a dependency added prematurely.

## Files that matter next

- `OctoTweaks/modules/aegis/Adapter.lua`
- `OctoTweaks/modules/aegis/UIAdapter.lua`
- `OctoTweaks/modules/aegis/MarketWorkbench.lua`
- `OctoTweaks/modules/aegis/MarketWorkbenchAegisUI.lua`
- `docs/modules/aegis.md`
- `docs/CURRENT_STATE.md`
- this work note

## Validation state

- backend source audit against Aegis 1.53.16: **DONE**;
- backend/source audit against Aegis 1.20.2: **DONE**;
- exact Aegis 1.20.2 private UI audit at commit `70f64849...`: **DONE**;
- phase-1 OctoWoW runtime validation: **PASS**;
- new Lua parse validation (`texluac -p`): **PASS**;
- focused mocked Aegis 1.20.2 UI integration smoke test: **PASS**;
- full repository `python tools/check.py` on the reconstructed push candidate: **PASS** (2026-09-15);
- parse validation of all addon Lua sources with `texluac -p`: **PASS** (2026-09-15);
- integrated Aegis sub-tab / Market Workbench v1 pricing workflow in OctoWoW: **PASS** — enablement, single-tab attachment, embedded layout/controls, plain-right-click Target selection, auto-search, auto-reference, persisted pricing, Suggested Price, and SellValue-backed vendor/gain display are confirmed.

## Next active milestone — safer automatic pricing

The v1 pricing path is stable enough for the push. The next implementation slice should improve automatic pricing safety before increasing posting speed:

1. add explicit `Manual`, `Exact-first`, and `Auto floor` reference policies;
2. add safeguards against isolated/absurdly low listings and a minimum acceptable relationship to vendor value;
3. keep the chosen reference explainable and manually overridable with `SET`;
4. preserve the current Aegis backend ownership and user-priority scan rules;
5. only after those safeguards are runtime-stable, implement **POST + NEXT**.

Background scanning, inventory analytics, and deeper market analytics remain explicitly out of scope for the immediate next slice.
