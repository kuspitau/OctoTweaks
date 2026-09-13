# Market Workbench — active handoff

## Goal

Build an OctoTweaks orchestration layer over Aegis: Exchange that keeps **Target Item** separate from **Reference Listing**, automatically searches comparable items, and eventually supports very short selling workflows without replacing Aegis' mature AH backend.

## Current implemented slice

This delta adds:

- `aegis.integration`: one version-aware/probed boundary around Aegis internals;
- `/otaegis` capability diagnostics;
- `aegis.market_workbench`: first UI prototype;
- Target Item selection from bags;
- automatic Similar Search by class/subclass/equipment slot and required-level range;
- optional buyout-only and exact-quality filtering;
- all-page result collection through Aegis scanning;
- grouped parent rows plus individual auction children;
- normal/Aegis-enhanced tooltips;
- independent Reference Listing selection;
- Match / Flat / Percent suggested pricing;
- safe tooltip opening for collected AH links;
- direct multi-stack posting through Aegis `sell.StartPosting`, with stack size, auction count, duration, progress and cancellation.

Deep embedding inside the Aegis window is deliberately still deferred.

## Important audit discoveries

Authoritative reusable detail is in `docs/modules/aegis.md`. The key architectural conclusions are:

- Aegis 1.53.16 and the user's installed 1.20.2 build have now both been source-audited for the internals used here. 1.20.2 exposes the expected scanner/category/database/sell helpers and explicitly documents cold `GetItemInfo` cache misses on 1.12. Runtime additionally showed that its last-number `util.ItemInfo` anchor shifts fields on this Octo client, so the adapter now validates that output and has a texture/equipLoc-anchored raw fallback.
- The Aegis source only labels its Courier integration block as a public contract. Other useful tables are internals and must remain behind `modules/aegis/Adapter.lua` capability probes.
- OctoTweaks does not bind to Aegis result-row/rendering internals, but AH-session detection must recognize Aegis' top-level frame because Aegis intentionally hides Blizzard `AuctionFrame` while preserving the server session.
- Aegis' scanner can pause/resume and its Buy engine understands active scanning, but the requested future idle-background priority scheduler does not yet exist as a reusable Aegis contract.

## Files that matter next

- `OctoTweaks/modules/aegis/Adapter.lua`
- `OctoTweaks/modules/aegis/MarketWorkbench.lua`
- `docs/modules/aegis.md`
- `docs/CURRENT_STATE.md`
- this work note

Aegis source audited upstream:

- `core/init.lua`
- `core/scan.lua`
- `core/buy.lua`
- `core/db.lua`
- `core/sell.lua`
- `ui/tooltip.lua`
- `README.md`

## Validation state

- source audit against Aegis 1.53.16: **DONE**;
- source audit against the user's installed Aegis 1.20.2 ZIP: **DONE**;
- Lua parse/static mocked validation for the phase-1 implementation: **PASS** when the implementation handoff was prepared;
- OctoWoW runtime validation on the user's Aegis 1.20.2 setup: **PASS for phase 1**.

Confirmed in game:

- Target Item capture and corrected item metadata;
- Similar Search from the custom Aegis AH UI;
- page polling/result collection;
- grouped result interaction;
- hover/tooltips after the vanilla full-link fix;
- independent Reference Listing selection through `SET`;
- Suggested Price calculation/display;
- direct Aegis-backed `POST`.

The phase-1 workflow can therefore be treated as the stable baseline for the next conversation.

## Next active milestone — integrate the Workbench into Aegis UI

The next conversation should move the validated Workbench presentation into the Aegis interface **without modifying Aegis files**. Prefer an additional Aegis sub-tab/panel or another minimally coupled UI extension over replacing Aegis' existing Buy/Sell views.

Constraints for that work:

- preserve the validated `Target → Similar Search → SET → POST` behavior;
- keep `modules/aegis/Adapter.lua` as the only boundary for version-sensitive Aegis internals;
- add capability/structure probes for every new Aegis UI internal used;
- reuse Aegis scanner, market DB, grouped Buy concepts, and Sell backend rather than duplicating them;
- keep a failure in the UI integration isolated so it cannot break other OctoTweaks modules or Aegis itself;
- do not expand into background scanning, inventory analytics, or deep statistics in the same slice unless required by the UI integration.

After the integrated UI is stable, the preferred next workflow enhancement is `POST + NEXT`, followed by automatic reference modes and the economic/inventory views described in the roadmap.
