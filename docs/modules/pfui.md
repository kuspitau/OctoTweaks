# pfUI Integration

## Scope

This document records version-scoped knowledge OctoTweaks relies on when extending pfUI externally.

Current reference version: **pfUI 5.5.4**.

Do not assume internal symbols remain stable across pfUI versions. Re-check structural assumptions when a module is changed or a new pfUI version is introduced.

## Known relevant internals

### libpredict

Observed in pfUI 5.5.4:

- file: `pfUI/libs/libpredict.lua`;
- named frame: `pfPredictionSender`;
- the frame has an `OnEvent` handler;
- the player `UNIT_SPELLCAST_START` branch calls `UnitCastingInfo("player")` and computes `endtime - starttime` without first validating both timestamps.

On the OctoWoW/SuperWoW client, an event associated with gathering/mining was observed to reach this path with `endtime == nil`, producing:

`attempt to perform arithmetic on local 'endtime' (a nil value)`

## OctoTweaks modules

### `pfui.libpredict_fix`

Source:

`OctoTweaks/modules/pfui/LibPredictFix.lua`

Strategy:

- locate `pfPredictionSender` externally;
- verify it exposes an existing `OnEvent` handler;
- wrap that handler;
- for player `UNIT_SPELLCAST_START`, call `UnitCastingInfo("player")`;
- if start/end timestamps are not numeric, return before the original pfUI handler reaches its unsafe subtraction;
- otherwise call the original handler unchanged.

Compatibility probe dependencies:

- `UnitCastingInfo` exists;
- `pfPredictionSender` exists;
- `GetScript`/`SetScript` exist on that frame;
- original `OnEvent` exists.

Reference validation target:

- pfUI 5.5.4.

Runtime validation: **PASS by sustained user observation (2026-09-21)**. The historical gathering/mining-related libpredict error has not recurred for a long period during normal OctoWoW use, and the user considers the fix closed. This records acceptance of the current behavior; it does not claim a newly instrumented reproduction of the original malformed event.

## Planned pfUI work

Possible future modules include friendly NPC/player nameplate differentiation and more granular nameplate text behavior. These are roadmap items only until implemented.
