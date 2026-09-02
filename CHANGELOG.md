# Changelog

All notable user-visible changes should be recorded here when preparing releases.

## Unreleased

### Added

- Initial OctoTweaks repository/bootstrap.
- Modular registry and runtime diagnostics.
- `pfui.libpredict_fix` compatibility module.
- `wow.extra_action_bars`: 96 persistent virtual action slots with configurable bars, action tooltips/cooldowns, native qbinds, quick-bind mode, and always/hover/toggle/hold visibility modes.
- Agent-oriented documentation and contribution protocol.
- Conversation-agent delta delivery policy.
- Root `addon_update.bat` for clean local deployment into OctoWoW.
- Standard-library-only repository checker and package builder under `tools/`.

### Changed

- `wow.extra_action_bars` regular macro drag/drop now captures the source macro from `PickupMacro()` to avoid incorrect OctoWoW cursor-index mappings; macro icon resolution, `UPDATE_MACROS` refresh, and `/otb macro <slot> <name/index>` fallback remain available.
- `wow.extra_action_bars` now uses `/otb` as its slash-command entry point; the `OTB` launcher can be moved with `Ctrl + drag` and toggled with `/otb ui`.

- `wow.extra_action_bars` item execution now prefers concrete bag/equipment locations and supports `/otb item <slot> <name/link/id>` fallback assignment.
- `wow.extra_action_bars` now supports Shift + left click move/swap between virtual slots and bars while keeping qbinds attached to logical slots.
- `wow.extra_action_bars` now has a compact settings panel for bar count, visual sizing, locking, Quick Bind, mode, columns, and scale.
- Extra-action slots now use exact-size borders with configurable button size, icon inset, and spacing.

### Fixed

- Fixed OTBar items rendering as solid colored squares by preferring concrete bag/equipment icon paths and rejecting non-path texture values.
- Fixed Shift + left click move/swap falling through to normal slot execution on OctoWoW by remembering the modifier at mouse-down time.
- Fixed action drops potentially triggering the destination slot on the same mouse release, which could immediately cast a dropped spell or use/equip a dropped item.
- Removed the native pushed/depressed slot texture that could remain stuck as blue/gold outlines after clicks on OctoWoW.
- Removed the visually padded native quickslot border that made occupied icons appear larger than empty slots.
