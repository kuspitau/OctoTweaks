# Warrior Assist — completed stable-baseline record — active work note

## Objective

Add a client-side Warrior smart-action feature to OctoTweaks for the user's multibox workflow. The player presses one key repeatedly; each press reads current local combat state, chooses at most one eligible Warrior action, and executes that one action through the native action slot that already contains the spell.

The feature is intentionally not an autonomous combat loop. No timer or `OnUpdate` handler casts abilities. One player key press produces zero or one `UseAction()` call.

## Current status

Implementation slice 1 + internal swing tracker + configurable Slam late-window tolerance: **IMPLEMENTED; STATIC VALIDATION COMPLETE; OCTOWOW RUNTIME VALIDATION PARTIAL**.

Runtime confirmed on 2026-09-15: initial Sunder, missing Battle Shout, Mortal Strike overflow selection, reserve-rage WAIT behavior, configured thresholds, the independent combat-log main-hand tracker, and Slam selection all behave as intended on the tested 2.90 s weapon. Overpower and Execute remain untested. The current slice adds a persisted late-window tolerance so the user can intentionally trade a small amount of swing clipping for more permissive Slam starts.

Module id: `wow.warrior_assist`
Source: `OctoTweaks/modules/wow/WarriorAssist.lua`
Binding: `OCTOTWEAKS_WARRIORASSIST_ACT`
Slash command: `/otwa`

## Development plan

### Phase 1 — smart-action engine and diagnostics

Implemented in the current delta:

- native Smart Action key binding plus `/otwa bind <KEY>` helper;
- native action-slot discovery across Blizzard slots 1..120 using ClassicAPI `GetActionInfo()` / `GetSpellInfo()`;
- no dependency on the user's ordinary per-spell key assignments;
- priority engine for Execute, Overpower, one initial Sunder Armor, Battle Shout maintenance, Mortal Strike overflow spending, and Slam;
- configurable post-Sunder rage reserve, default 15;
- configurable Mortal Strike overflow threshold, default 55 rage;
- aura checks for Battle Shout and Sunder Armor;
- readiness checks through `IsUsableAction`, range, and native action cooldown state;
- safe-Slam gating from an explicit numeric swing-progress source, now primarily an internal combat-log tracker with SuperCleveRoidMacros, SP_SwingTimer, and pfUI as fallbacks;
- internal swing reset from 1.12 `CHAT_MSG_COMBAT_SELF_HITS` / `CHAT_MSG_COMBAT_SELF_MISSES` white swings plus `Heroic Strike` / `Cleave` on-next-swing replacements, cross-checked against the user-supplied AttackBar 5.0.7 event strategy without creating an AttackBar dependency;
- configurable Slam late-window tolerance, default 0.30 s, via `/otwa slamtolerance <seconds>` (alias `/otwa slamlate`);
- per-action enable/disable and rage-cost overrides;
- `/otwa status`, `/otwa scan`, and optional decision debug output;
- event-driven action-slot rescans on entering world, action-bar changes, and spell changes.

### Phase 2 — runtime calibration

Do not expand the combat policy until the first OctoWoW runtime pass establishes the following:

- ClassicAPI rage-cost units returned by `C_Spell.GetSpellPowerCost()` on the user's client; `/otwa status` should show display costs such as approximately 10/15/30 rage rather than raw engine units;
- whether `IsUsableAction()` correctly exposes the desired Execute and Overpower windows on this client;
- actual Slam cast time with the user's current Improved Slam rank/talents; the corrected path auto-resolves from SuperCleveRoidMacros tooltip timing first, then ClassicAPI spell info, with `/otwa slamcast <seconds>` retained as an override;
- numeric swing progress from the internal tracker is now runtime-confirmed; `/otwa slamprobe` prints source/progress/timing-window details plus tracker age/duration/reset reason;
- practical Slam late tolerance: start from the new 0.30 s default and tune with `/otwa slamtolerance 0`, `0.30`, `0.50`, etc. according to desired clip/DPS tradeoff;
- whether the `HARMFUL|PLAYER` aura filter identifies the Warrior's Sunder reliably or the documented any-Sunder fallback is used;
- practical Mortal Strike overflow threshold after several fights.

Use `/otwa cost <action> <rage>` as a temporary runtime override if the power-cost unit contract differs from the source-audited expectation.

### Phase 3 — later extensions after the base loop is stable

Candidates, not part of the current implementation:

- a separate universal interrupt intent/button with stance/equipment-aware Pummel vs Shield Bash handling;
- optional compact visual indicator showing the currently predicted Smart Action / WAIT reason;
- explicit stance-aware policies where a concrete gameplay need justifies them;
- integration with OctoTweaks Extra Action Bars or a future QuickLayout/profile layer;
- further combat modes only after measured runtime behavior demonstrates a need.

## Priority policy in phase 1

For a valid hostile target while the Warrior is already in combat:

1. Execute if its native action is currently usable;
2. Overpower if usable and its cost leaves the configured reserve;
3. Sunder Armor if the target has no visible Sunder, allowing this initial Sunder to dip below the reserve;
4. Battle Shout if missing and its cost leaves the reserve;
5. Mortal Strike if current rage is at or above the configured overflow threshold and its cost leaves the reserve;
6. Slam if its cost leaves the reserve and the safe-Slam timing check passes;
7. otherwise do nothing.

This ordering is deliberately configurable rather than treated as final theorycraft. The first goal is predictable input handling and runtime observability.

## Compatibility assumptions

The current implementation requires the OctoWoW ClassicAPI functions `GetActionInfo`, `GetSpellInfo`, and `C_UnitAuras.GetAuraDataBySpellName`. Managed spells must exist somewhere in Blizzard's native action slots 1..120. Their normal key bindings may be changed freely.

Current spell matching uses English spell names. The user's current client is expected to use those names; localization support is not implemented yet.

Safe Slam still requires numeric swing progress when enabled, but the accepted start window is no longer strictly no-clip: the default late tolerance is 0.30 s and is user-configurable. Warrior Assist normally supplies swing progress itself from self-combat messages and `UnitAttackSpeed()`. A `false` result from SuperCleveRoidMacros' legacy `ValidateNoSlamClip()` is not treated as authoritative because that function also returns false when its timer source is unavailable. AttackBar is source-reference only and is not required or queried at runtime. Dual-wield swing disambiguation remains outside the currently validated scope.

## Runtime validation required

1. Overlay the delta, run `tools\check.bat`, then run root `addon_update.bat` and `/reload` or restart WoW.
2. On the Warrior, run `/ot status` and confirm `wow.warrior_assist = ENABLED`.
3. Put Execute, Overpower, Sunder Armor, Battle Shout, Mortal Strike, and Slam somewhere in native Blizzard action slots; they may be on otherwise hidden bars.
4. Run `/otwa scan` then `/otwa status`. Confirm every required action has a slot and that reported rage costs are sensible display values.
5. Bind Smart Action through the WoW Key Bindings UI or `/otwa bind <KEY>`.
6. With no hostile target and while out of combat, press Smart Action and confirm it never initiates a pull.
7. Enter combat on a fresh mob. Confirm the first eligible setup press applies one Sunder and later presses stop choosing Sunder once the debuff is visible.
8. Remove Battle Shout and build enough rage. Confirm Smart Action restores it once while preserving the configured post-Sunder reserve.
9. Set `/otwa reserve 15`. At low rage, verify Slam/MS are withheld when their cost would leave less than 15 rage.
10. Trigger an enemy dodge. Confirm an available Overpower takes priority on the next eligible press.
11. Put the target into Execute range. Confirm Execute takes priority on the next press.
12. With rage at/above the default 55 threshold, confirm ready Mortal Strike is chosen before Slam; adjust `/otwa ms <rage>` only after observing real fights.
13. Run `/otwa slamprobe` immediately after a visible white hit. Confirm `swing=` is numeric with source `internal combat-log tracker` and the tracker line shows a small age against approximately 2.90 s. Compare `/otwa slamtolerance 0`, `0.30`, and optionally `0.50`; confirm the reported `safe<=` threshold and actual Slam acceptance move later by the requested amount. Use `/otwa slamcast <seconds>` only if the auto-resolved cast time is wrong; `/otwa slamcast auto` removes the override.
14. Move one managed spell to another native action slot or change its normal key binding. Confirm the next action-bar rescan keeps Smart Action functional; use `/otwa scan` to force a diagnostic rescan if needed.
15. Confirm repeated key presses never produce more than one action attempt per press.

## Validation already performed by the conversation agent

- `texluac -p` parses `WarriorAssist.lua` successfully.
- `Bindings.xml` parses as XML successfully.
- Focused Lua 5.0/source guard checks and a mocked priority smoke test are part of this handoff's final validation report.
- OctoWoW runtime validation is **PASS by user acceptance (2026-09-21)**. Earlier staged evidence confirmed Sunder, Battle Shout, Mortal Strike overflow, reserve preservation, configured thresholds, the internal combat-log tracker, and Slam selection; the user subsequently confirmed Warrior Assist works well and explicitly closed validation. This acceptance does not claim separate instrumented observations for every reactive branch.

## Relevant files

- `OctoTweaks/modules/wow/WarriorAssist.lua`
- `OctoTweaks/Bindings.xml`
- `OctoTweaks/OctoTweaks.toc`
- `docs/modules/wow.md`
- `docs/CURRENT_STATE.md`
- `CHANGELOG.md`

## Important open points

Runtime testing confirmed that the current rage thresholds and reserve behavior are operational for Sunder/Battle Shout/Mortal Strike on the user's client. No reactive-action validation debt remains after user acceptance of the current baseline.

The prior Slam failure is resolved: the internal tracker produces usable progress and Smart Action now casts Slam. The remaining Slam work is tuning the permissive late-window value against actual DPS/feel; the user can change it without code edits through `/otwa slamtolerance`. Mortal Strike cooldown fall-through is already confirmed not to block Slam.

The module is now closed as a stable accepted baseline. Future changes should revalidate only the behavior they plausibly affect.


## Closure

This note is historical implementation/validation context. Current truth is `docs/CURRENT_STATE.md` and `docs/modules/wow.md`.
