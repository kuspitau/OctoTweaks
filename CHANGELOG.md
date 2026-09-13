# Changelog

All notable user-visible changes should be recorded here when preparing releases.

## Unreleased

### Added

- Initial OctoTweaks repository/bootstrap.
- Modular registry and runtime diagnostics.
- `pfui.libpredict_fix` compatibility module.
- `wow.extra_action_bars`: 96 persistent virtual action slots with configurable bars, action tooltips/cooldowns, native qbinds, quick-bind mode, and always/hover/toggle/hold visibility modes.
- `aegis.integration`: version-aware capability adapter and `/otaegis` diagnostics for source-audited Aegis: Exchange 1.20.2 and 1.53.16 internals used by OctoTweaks.
- `aegis.market_workbench`: Market Workbench with persistent Target Item, automatic Similar Search, grouped results/tooltips, independent Reference Listing selection, Match/Flat/% suggested pricing, and direct Aegis-backed multi-stack posting controls.
- Agent-oriented documentation and contribution protocol.
- Conversation-agent delta delivery policy.
- Root `addon_update.bat` for clean local deployment into OctoWoW.
- Standard-library-only repository checker and package builder under `tools/`.

### Changed

- Aegis Market Workbench phase 1 is now runtime-validated on the user's Aegis 1.20.2 setup for Target selection, Similar Search/polling, tooltips, `SET`, Suggested Price, and direct `POST`; the next active milestone is Aegis-window UI integration.
- `wow.extra_action_bars` regular macro drag/drop now captures the source macro from `PickupMacro()` to avoid incorrect OctoWoW cursor-index mappings; macro icon resolution, `UPDATE_MACROS` refresh, and `/otb macro <slot> <name/index>` fallback remain available.
- `wow.extra_action_bars` now uses `/otb` as its slash-command entry point; the `OTB` launcher can be moved with `Ctrl + drag` and toggled with `/otb ui`.

- `wow.extra_action_bars` item execution now prefers concrete bag/equipment locations and supports `/otb item <slot> <name/link/id>` fallback assignment.
- `wow.extra_action_bars` now supports Shift + left click move/swap between virtual slots and bars while keeping qbinds attached to logical slots.
- `wow.extra_action_bars` now has a compact settings panel for bar count, visual sizing, locking, Quick Bind, mode, columns, and scale.
- Extra-action slots now use exact-size borders with configurable button size, icon inset, and spacing.

### Fixed

- Fixed Workbench result hover on vanilla clients that reject full coloured AH hyperlinks in `GameTooltip:SetHyperlink`; the adapter now prefers verified live AH rows and otherwise uses a bare `item:...` payload under `pcall`.
- Fixed Market Workbench metadata on the tested Octo/Aegis 1.20.2 client by rejecting shifted Aegis `util.ItemInfo` output and falling back to a texture/equipment-location anchored raw `GetItemInfo` normalizer; diagnostics now print raw returns through slot 12.
- Fixed Similar Search incorrectly requiring the Blizzard auction window to be visible; Aegis' custom AH frame now counts as an open auction-house session.
- Fixed Market Workbench Target Item selection on cold 1.12 item caches by warming bag-item tooltip data, retrying Aegis `util.ItemInfo`, and adding `/otmarket itemprobe <bag> <slot>` diagnostics.
- Fixed OTBar items rendering as solid colored squares by preferring concrete bag/equipment icon paths and rejecting non-path texture values.
- Fixed Shift + left click move/swap falling through to normal slot execution on OctoWoW by remembering the modifier at mouse-down time.
- Fixed action drops potentially triggering the destination slot on the same mouse release, which could immediately cast a dropped spell or use/equip a dropped item.
- Removed the native pushed/depressed slot texture that could remain stuck as blue/gold outlines after clicks on OctoWoW.
- Removed the visually padded native quickslot border that made occupied icons appear larger than empty slots.
