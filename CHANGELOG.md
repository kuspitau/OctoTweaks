# Changelog

All notable user-visible changes should be recorded here when preparing releases.

## Unreleased

### Added

- Market Workbench quick-right-click pricing flow: selecting a bag Target from the integrated Workbench now starts Similar Search automatically, auto-selects the first priced result as Reference on completion, preserves the user's existing undercut preset, and shows a color-banded gross `Gain vs vendor` value below Suggested Price. Gain cutoffs persist and can be inspected/changed with `/otmarket gains`.
- Initial OctoTweaks repository/bootstrap.
- Modular registry and runtime diagnostics.
- `pfui.libpredict_fix` compatibility module.
- `wow.extra_action_bars`: 96 persistent virtual action slots with configurable bars, action tooltips/cooldowns, native qbinds, quick-bind mode, and always/hover/toggle/hold visibility modes.
- `aegis.integration`: version-aware capability adapter and `/otaegis` diagnostics for source-audited Aegis: Exchange 1.20.2 and 1.53.16 internals used by OctoTweaks.
- `aegis.market_workbench`: Market Workbench with persistent Target Item, automatic Similar Search, grouped results/tooltips, independent Reference Listing selection, Match/Flat/% suggested pricing, and direct Aegis-backed multi-stack posting controls.
- `aegis.market_workbench_ui`: exact-version-probed Aegis 1.20.2 `Workbench` sub-tab integration that externally appends an Aegis panel, reuses the existing Workbench presentation, routes `/otmarket` into Aegis while the AH is open, and retains standalone fallback without modifying Aegis files.
- Agent-oriented documentation and contribution protocol.
- Conversation-agent delta delivery policy.
- Root `addon_update.bat` for clean local deployment into OctoWoW.
- Standard-library-only repository checker and package builder under `tools/`.

### Changed

- The hosted Workbench quick-pricing chain is now runtime-confirmed through automatic Similar Search, first-priced Reference selection, and reuse of the user's persisted Percent-5 preset; manual controls remain available as overrides.
- Aegis Market Workbench v1 is runtime-validated on the user's Aegis 1.20.2 setup through the hosted quick-pricing chain and corrected SellValue-backed vendor/gain display; manual `SET` and Aegis-backed posting remain available as overrides/actions.
- Aegis private presentation access is isolated in `modules/aegis/UIAdapter.lua` and exact-version-gated to Aegis 1.20.2 commit `70f64849...`; backend integration remains independent so an incompatible UI seam cannot disable the validated standalone workflow.
- `wow.extra_action_bars` regular macro drag/drop now captures the source macro from `PickupMacro()` to avoid incorrect OctoWoW cursor-index mappings; macro icon resolution, `UPDATE_MACROS` refresh, and `/otb macro <slot> <name/index>` fallback remain available.
- `wow.extra_action_bars` now uses `/otb` as its slash-command entry point; the `OTB` launcher can be moved with `Ctrl + drag` and toggled with `/otb ui`.

- `wow.extra_action_bars` item execution now prefers concrete bag/equipment locations and supports `/otb item <slot> <name/link/id>` fallback assignment.
- `wow.extra_action_bars` now supports Shift + left click move/swap between virtual slots and bars while keeping qbinds attached to logical slots.
- `wow.extra_action_bars` now has a compact settings panel for bar count, visual sizing, locking, Quick Bind, mode, columns, and scale.
- Extra-action slots now use exact-size borders with configurable button size, icon inset, and spacing.

### Fixed

- Fixed `Gain vs vendor` using unavailable Aegis vendor data on items where SellValue already knew the merchant price: the Workbench now prefers SellValue's read-only `SellValues["item:<id>"]` value, falls back to Aegis when needed, mirrors the resolved vendor into the Target-market summary, and gives the gain label a larger dedicated row below Suggested Price.
- Fixed embedded Workbench controls disappearing/becoming non-interactive after reparenting into Aegis: all pre-existing child frames are now rebased above the Aegis content layer, restoring the Similar Search, filter, result, pricing and posting controls while preserving the separately hardened Target box.
- Fixed embedded Workbench Target interaction after the first Aegis-hosted runtime pass: the drop target is explicitly re-enabled/raised with a cursor-item mouse-up fallback, and a faster plain-right-click-on-bag-item path now selects Target while Workbench is active without hijacking modified clicks or inventory clicks elsewhere.
- Fixed Workbench result hover on vanilla clients that reject full coloured AH hyperlinks in `GameTooltip:SetHyperlink`; the adapter now prefers verified live AH rows and otherwise uses a bare `item:...` payload under `pcall`.
- Fixed Market Workbench metadata on the tested Octo/Aegis 1.20.2 client by rejecting shifted Aegis `util.ItemInfo` output and falling back to a texture/equipment-location anchored raw `GetItemInfo` normalizer; diagnostics now print raw returns through slot 12.
- Fixed Similar Search incorrectly requiring the Blizzard auction window to be visible; Aegis' custom AH frame now counts as an open auction-house session.
- Fixed Market Workbench Target Item selection on cold 1.12 item caches by warming bag-item tooltip data, retrying Aegis `util.ItemInfo`, and adding `/otmarket itemprobe <bag> <slot>` diagnostics.
- Fixed OTBar items rendering as solid colored squares by preferring concrete bag/equipment texture APIs first and rejecting non-path texture values.
- Fixed Shift + left click move/swap falling through to normal slot execution on OctoWoW by remembering the modifier at mouse-down time.
- Fixed action drops potentially triggering the destination slot on the same mouse release, which could immediately cast a dropped spell or use/equip a dropped item.
- Removed the native pushed/depressed slot texture that could remain stuck as blue/gold outlines after clicks on OctoWoW.
- Removed the visually padded native quickslot border that made occupied icons appear larger than empty slots.
