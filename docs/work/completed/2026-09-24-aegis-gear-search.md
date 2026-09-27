# Aegis Gear Search — completed baseline

## Objective

Extend the initial Aegis-hosted Gear Search into a reusable equipment-search tool: repair cold-cache Slot/Type metadata, add local target-slot filtering, generalize stat parsing/scoring, and make stat visibility/minimum/weight composition preset-owned.

## Final status

**STABLE — implementation and current OctoWoW/Aegis 1.53.29 behavior accepted by the user on 2026-09-27.**

Earlier runtime testing had shown a specific cold-cache failure where sortable results worked but Slot/Type remained `--`. The completed implementation uses Aegis scan subtype metadata plus readable tooltip equipment-location text as fallbacks, and the user subsequently confirmed the recently added features are working.

## Completed work

- Added `aegis.gear_search` and its Aegis scanner/category adapter.
- Added the shared multi-extension Aegis UI registry so Workbench and Gear Search coexist without replacing Aegis files.
- Preserved Aegis ownership of query pacing/page traversal and added `gear_search` query ownership isolation.
- Added category/slot/level/quality/price filters, suffix-aware variant reduction and batched tooltip parsing.
- Added generic stat registry, per-stat Show/Min/Weight controls, weighted scoring and up to eight sortable displayed stat columns.
- Added layered Type/Slot metadata fallback for cold item caches.
- Added built-in/editable presets plus named user preset save/load/delete and additive schema migration through schema 3.
- Preserved local ownership cleanup when leaving Gear Search or closing the AH.

## Relevant files

- `OctoTweaks/modules/aegis/UIExtensions.lua`
- `OctoTweaks/modules/aegis/GearSearchAdapter.lua`
- `OctoTweaks/modules/aegis/GearSearch.lua`
- `docs/modules/aegis.md`
- `docs/modules/aegis-gear-search.md`

## Durable implementation choices

- Higher-level Gear Search logic uses the OctoTweaks Aegis adapter rather than direct `AegisExchange.*` access.
- Slot filtering remains post-scan/local; correctness was preferred over speculative query narrowing.
- Type fallback may use the resolved Aegis query subclass; Slot fallback may use tooltip equipment-location text already proven readable on the client.
- Show, Min and Weight are independent dimensions. Hidden stats may still score/filter.
- Eight visible stat columns is a presentation cap, not a parser/scoring cap.

## Validation evidence

Before final runtime acceptance, the implementation had passed targeted Lua parsing/guardrail and smoke tests for schema migration, metadata fallback, minimum filtering, adapter metadata propagation, stat-editor construction and preset migration. The user then accepted the current recent feature set in game on 2026-09-27.

Reusable future regression steps are maintained in `docs/modules/aegis-gear-search.md`; this completed note is historical evidence and is not part of the normal agent reading path.
