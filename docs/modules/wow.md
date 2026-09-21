# WoW / OctoWoW Client Features

## Scope

This document records OctoTweaks features that target the WoW 1.12 / OctoWoW client itself rather than a third-party addon.

## `wow.extra_action_bars`

Source:

`OctoTweaks/modules/wow/ExtraActionBars.lua`

Binding declarations:

`OctoTweaks/Bindings.xml`

Category: **feature**
Target: **WoW 1.12 / OctoWoW client UI**
Default: **enabled**
Implementation: **IMPLEMENTED — runtime iteration 6**
In-game validation: **PASS by user acceptance (2026-09-21)** — current spell/item/macro behavior is accepted as working on OctoWoW

### Purpose

Provide persistent action slots beyond Blizzard's native action-slot pool while preserving action-bar-like interaction:

- stable logical slot ids;
- visible buttons with icons, key labels, item counts, cooldowns where directly resolvable, and tooltips;
- persistent spell/item/macro/SuperMacro assignments;
- native WoW key bindings that remain usable when the corresponding visual bar is hidden;
- bars that can be always visible, hover-revealed, toggled, or visible only while a hold binding is pressed.

### Runtime observations so far

The first OctoWoW test confirmed that:

- the module loads far enough to create the four default bars;
- spells can be dropped onto virtual slots and their icons appear.

The same test exposed two visual issues in the first prototype:

1. the native `UI-Quickslot2` texture has visual padding, so the visible empty-slot outline looked materially smaller than the actual button/icon area;
2. the native pushed-state texture could remain visible after clicking a slot, producing persistent blue/gold outlines.

Iteration 2 removes both native textures from the slot shell. Slots now use an exact-size one-pixel border and no persistent pushed texture. The resulting current UI is included in the user-accepted stable baseline.

A later runtime test found two interaction problems: Shift + left click could reach normal slot execution instead of the internal move path, and dropping an item could be followed by a destination click that immediately used/equipped the just-assigned item. Iteration 4 records Shift at mouse-down time and suppresses the post-drop click. Item assignment is also hardened for equippable items and item-link/id resolution. The resulting behavior is included in the user-accepted stable baseline.

A later runtime test confirmed that item assignment/use works, including equippable items, but item icons rendered as a solid red square. Iteration 5 treats this as an icon-resolution compatibility issue: item textures are resolved from the concrete bag slot via `GetContainerItemInfo()` or equipped slot via `GetInventoryItemTexture()` first. `GetItemInfo()` and stored texture values are accepted only when they are non-empty strings, preventing numeric/non-path values from being passed to `SetTexture()`. The user subsequently confirmed that the corrected item icons render properly in OctoWoW.

Regular macro drag/drop is supported, but OctoWoW runtime testing exposed that the numeric token observed from `GetCursorInfo()` is not a reliable macro index for every macro (observed examples included macro 1 resolving as 2, macro 2 as 4, and macro 4 as unavailable index 5). OTBar therefore captures the authoritative macro identity from the public `PickupMacro()` call at drag start and uses that captured action at drop time when it matches the current macro cursor. The raw cursor token remains only a fallback for code paths that do not call `PickupMacro()`. OTBar stores both macro name and resolved index, resolves numeric macro-icon identifiers through `GetMacroIconInfo()`, refreshes on `UPDATE_MACROS`, and provides `/otb macro <slot> <name/index>` as a manual fallback. The user subsequently accepted the current regular-macro behavior as working and closed this validation item (2026-09-21).

### Capacity and layout

The module exposes a fixed logical capacity of **96 virtual slots**, grouped as **8 bars × 12 slots**. Four bars are active on first initialization; `barCount` can expose between 1 and 8 bars without destroying assignments in inactive bars.

Default bar modes are:

1. `always`
2. `always`
3. `hover`
4. `toggle`

Bars 5-8 default to `always` if later activated.

Global visual defaults for iteration 2 are:

- button size: **30 px**;
- icon margin/inset: **2 px**;
- slot spacing: **1 px**.

These three values are persisted under `OctoTweaksDB.extraActionBars` and can be changed live from the settings panel or slash commands. Existing first-prototype SavedVariables receive these additive defaults automatically; slot assignments and bindings are not reset.

Each bar separately supports:

- 1-12 columns;
- scale 0.5-2.0;
- drag positioning while unlocked;
- persisted point/offset/scale/columns/mode.

### Moving and locking bars

When bars are **unlocked**, each active bar exposes a small handle above it labelled `OT1`, `OT2`, etc. Drag that handle with the left mouse button to move the bar.

When bars are **locked**, the handles are hidden and normal visibility modes are applied.

The settings panel contains a `Lock bars` / `Unlock bars` control and also displays a short movement hint. `Shift + Right Click` on the `OTB` launcher remains a fast lock/unlock shortcut.

### Settings panel

Iteration 2 adds a dedicated compact settings frame.

Open it with either:

- **Right Click** on the `OTB` launcher; or
- `/otb config` (alias `/otb settings`).

The panel currently exposes:

Global settings:

- active bar count;
- button size (22-48 px);
- icon margin/inset (1-8 px);
- slot spacing (0-10 px);
- lock/unlock;
- Quick Bind on/off;
- reset layout and visual sizing.

Selected-bar settings:

- bar selector;
- visibility mode (`always` -> `hover` -> `toggle` -> `hold`);
- columns;
- per-bar scale;
- toggle selected bar when it is in `toggle` mode.

The settings window itself can be moved by dragging its title area.

### `OTB` launcher

The small `OTB` launcher provides:

- left click: toggle all `toggle`-mode bars;
- middle click: enter/leave quick-bind mode;
- right click: open/close the settings panel;
- Shift + right click: lock/unlock bars;
- `Ctrl + drag`: move the launcher, independently of the bar lock state.

### Stored actions

Assignments are stored under `OctoTweaksDB.extraActionBars.slots` and currently support:

- `spell` — stored by spell name/rank with cached texture; resolved back to the spellbook before cast;
- `item` — stored by item id/name/link when available; resolved from bags/equipment for use and cooldown/count display;
- `macro` — stored by regular macro name and resolved at execution time;
- `supermacro` — stored by SuperMacro name and executed through `RunSuperMacro` when that optional addon is available.

A spell, item, or regular macro can be assigned by dragging it onto a slot. Item drops are stored without activating the item on the same mouse release. This is important for equippable objects such as fishing poles. As fallback/manual assignment paths:

`/otb item <slot> <item name, link, or id>`

`/otb macro <slot> <regular macro name or index>`

Regular macros are persisted primarily by name, with the observed macro index retained as a fast/exact hint when it still resolves to the same name. This avoids accidentally running a different macro if macro slots are later reordered. Macro icon values that are numeric are resolved through `GetMacroIconInfo()` before rendering.

SuperMacros are assigned explicitly with:

`/otb super <slot> <SuperMacro name>`

Shift + left click on a populated slot selects its virtual action for an internal move. Shift + left click a second slot to complete the move; if the destination is already populated, the two actions are swapped. The qbinds remain attached to the logical source/destination slots and are not moved with the action. Shift + left click the selected source again to cancel. The selected source displays a small gold `M` marker until the move is completed or cancelled.

Shift + right click on a slot clears its action assignment but does not clear its key binding.

### Bindings

`Bindings.xml` declares one native binding command for each logical slot plus utility commands for toggle and hold visibility. It is intentionally **not** listed in the TOC; WoW loads an addon's `Bindings.xml` through the normal binding mechanism.

Slot bindings call `OctoTweaks_ExtraBars_UseSlot(<id>)` directly. They do not depend on Blizzard action ids and do not click the visual button. This is the invariant that lets a qbind continue to execute while its bar is hidden.

Bindings are saved with the client's active binding set using `SetBinding` + `SaveBindings(GetCurrentBindingSet())`.

Quick-bind mode can be entered with middle click on `OTB`, the settings panel, or `/otb qbind`. While active:

- hover a virtual slot and press a keyboard key/combo to bind it;
- side mouse buttons can be captured from the hovered button;
- `ESC` while hovering a slot clears that slot's binding;
- `ESC` while not hovering a slot exits quick-bind mode.

The ordinary WoW Key Bindings UI can also bind every declared extra slot and the two utility commands.

### Visibility modes

- `always` — normal action bar.
- `hover` — remains present at very low alpha and becomes fully visible while hovered.
- `toggle` — shown/hidden by the `OTB` launcher, `/otb toggle`, or the utility binding.
- `hold` — shown only while the hold binding is pressed; the binding uses `runOnUp="true"` so key-down and key-up can be distinguished.

While bars are unlocked, active bars are forced visible to make configuration possible. Locking re-applies their configured visibility modes.

### Commands

Primary command: `/otb`.

Important subcommands:

- `/otb config`
- `/otb status`
- `/otb lock` / `/otb unlock`
- `/otb qbind [on|off]`
- `/otb bars <1-8>`
- `/otb mode <bar> <always|hover|toggle|hold>`
- `/otb cols <bar> <1-12>`
- `/otb scale <bar> <0.5-2.0>`
- `/otb size <22-48>`
- `/otb spacing <0-10>`
- `/otb inset <1-8>`
- `/otb toggle [bar]`
- `/otb ui` (toggle launcher)
- `/otb ui <on|off>`
- `/otb resetlayout`
- `/otb bind <slot> <KEY>` / `/otb unbind <slot>`
- `/otb bindtoggle <KEY>` / `/otb bindhold <KEY>`
- `/otb clear <slot>`
- `/otb item <slot> <item name, link, or id>`
- `/otb macro <slot> <regular macro name or index>`
- `/otb super <slot> <SuperMacro name>`

### Compatibility assumptions and current limitations

The module deliberately avoids pfUI internals and can coexist with pfUI without patching it. `pfUI` is not required for the feature.

Current limitations / future enhancements:

- the new settings panel is custom OctoTweaks UI rather than pfUI's own configuration framework;
- range coloring and generic `IsUsableAction`-style state are not available for every virtual action type;
- direct spell and item cooldowns are displayed, but arbitrary macro/SuperMacro cooldown inference is not attempted;
- direct SuperMacro drag/drop is not implemented; use `/otb super`;
- dragging an already-populated Blizzard action-button slot as cursor type `action` is not yet imported;
- assignments are persistent but there is no profile layer or QuickLayout profile integration yet;
- the 96-slot maximum remains fixed so stable binding command names can be declared statically.

### Regression checklist for future OTBars changes

1. Apply the new delta, deploy, then `/reload` or restart the client.
2. Confirm the four bars still appear and previously assigned spells remain assigned.
3. Compare empty and occupied slots: icon, border, and clickable area should now be the same physical size.
4. Click an empty slot, then move the mouse away: no blue pushed-state outline should remain.
5. Click a populated spell slot, then move the mouse away: no gold/depressed outline should remain.
6. Right-click `OTB`; confirm the settings panel opens. Change button size, icon margin, and spacing and verify live relayout.
7. In the settings panel click `Unlock bars`; verify the `OT1` / `OT2` handles are visible and dragging them moves the corresponding bars. Lock again and verify handles disappear.
8. Put actions in two different slots, including slots on different bars. Hold Shift before pressing the left mouse button on the first action. Confirm the spell/item is **not executed**, a small gold `M` marker appears, then Shift + left click the second slot. Confirm the actions move/swap and each slot keeps its original qbind. Repeat with an empty destination and confirm the source becomes empty.
9. Shift + left click a populated slot twice and confirm the move selection cancels without changing either action or executing it.
10. Drag a normal bag item onto an empty OTBar slot. Confirm the item remains assigned and is not immediately used on drop. Then click the slot normally and confirm the item is used.
11. Repeat with an equippable item such as a fishing pole: drop it onto a slot without equipping it immediately, then normal-click/qbind the slot and confirm it equips/uses correctly. If drag/drop is still client-specific, test `/otb item <slot> <item name>` as the fallback.
12. Change the selected bar, its columns, scale, and visibility mode from the panel.
13. `/reload`; confirm visual settings, bar positions, slot assignments, and qbinds persist.
14. Continue the original validation for qbinds, hidden-bar execution, hold mode, macros/SuperMacros, cooldowns, counts, zoning, and combat.

## `wow.warrior_assist`

Source:

`OctoTweaks/modules/wow/WarriorAssist.lua`

Binding declaration:

`OCTOTWEAKS_WARRIORASSIST_ACT` in `OctoTweaks/Bindings.xml`

Category: **feature**
Target: **WoW 1.12 / OctoWoW Warrior client**
Default: **enabled**
Implementation: **INITIAL SMART-ACTION SLICE IMPLEMENTED**
In-game validation: **PASS by user acceptance (2026-09-21)** — current Smart Action baseline is accepted as working on the user's Warrior

### Purpose and input boundary

Warrior Assist provides one manually triggered Smart Action for a Warrior being managed alongside another character. It is an intent-level button rather than a fixed spell binding.

On every press the module:

1. reads current local target/combat/rage/aura/action state;
2. selects zero or one eligible managed action;
3. calls `UseAction()` on exactly that one discovered native action slot, or does nothing.

It does **not** run a combat action loop from `OnUpdate`, timers, combat events, or another character. Events refresh the local action-slot map and maintain passive swing-timing state only; they never execute a managed action. The actual action boundary remains one player input -> zero or one action attempt.

### Managed actions and native-slot discovery

The current managed set is:

- Execute;
- Overpower;
- Sunder Armor;
- Battle Shout;
- Mortal Strike;
- Slam.

The module scans Blizzard native action slots 1..120 with ClassicAPI `GetActionInfo()` and resolves spell ids with `GetSpellInfo()`. If multiple ranks of the same managed spell appear, the highest numerically labelled rank is selected.

This deliberately decouples Warrior Assist from the user's ordinary bindings. The player may move Mortal Strike from one key to another without changing the smart-action policy. The requirement is only that each managed spell remain present somewhere in the native action-slot table. `ACTIONBAR_SLOT_CHANGED`, `SPELLS_CHANGED`, and `PLAYER_ENTERING_WORLD` trigger rescans; `/otwa scan` forces one manually.

Current matching uses English spell names. Localization-independent spell-id/rank-family discovery remains future work if needed.

### Phase-1 priority

For a valid hostile target when the Warrior is already in combat, the current priority is:

1. **Execute** if its native action is usable;
2. **Overpower** if usable and paying for it leaves the configured rage reserve;
3. **Sunder Armor** when no visible Sunder is present on the target; this initial setup Sunder is the sole normal spender allowed to dip below the reserve;
4. **Battle Shout** when absent and paying for it leaves the reserve;
5. **Mortal Strike** when current rage is at/above the configured overflow threshold and paying for it leaves the reserve;
6. **Slam** when usable, paying for it leaves the reserve, and the safe-Slam timing gate passes;
7. otherwise **WAIT** and issue no action.

Defaults:

- reserve rage: **15**;
- Mortal Strike overflow threshold: **55**;
- safe Slam: **enabled**;
- Slam cast time: **auto-resolved** (SuperCleveRoidMacros tooltip helper -> ClassicAPI spell info -> 2.0 s conservative fallback), with an optional manual override;
- Slam safety margin: **0.05 s**;
- Slam late-window tolerance: **0.30 s** by default, configurable with `/otwa slamtolerance <seconds>` (alias `/otwa slamlate`).

The ordering is a testable initial policy, not a claim that the thresholds are final theorycraft. Runtime observations should drive later tuning.

### Target/combat guard

Smart Action intentionally does not perform a pull. It returns WAIT when:

- there is no target;
- the target is dead;
- the target is not hostile/attackable;
- the Warrior is not already in combat.

This lets the user keep one Smart Action binding permanently active without a separate start/stop mode.

### Rage reserve and spell-cost handling

`GetRage()` prefers `UnitPower("player", 1)` and falls back to the vanilla `UnitMana("player")` convention when needed.

Spell costs are obtained in this order:

1. per-action SavedVariables override from `/otwa cost`;
2. ClassicAPI `C_Spell.GetSpellPowerCost(spellID)`;
3. conservative phase-1 fallback constants.

The source-audited ClassicAPI path is normalized from raw rage units to display rage with the vanilla divisor of 10. The current Smart Action baseline is user-accepted on the target OctoWoW setup; `/otwa status` still prints effective cost/source and `/otwa cost <action> <rage>` remains available as a safe calibration override for future client/API changes.

Except for the initial Sunder, spenders are rejected when:

`current rage - effective cost < configured reserve`.

Execute is treated as the terminal priority and is not reserve-gated.

### Auras

Battle Shout is checked through:

`C_UnitAuras.GetAuraDataBySpellName("player", "Battle Shout", "HELPFUL")`.

Sunder first attempts a player-owned harmful aura filter. Some ClassicAPI builds may not support the combined `HARMFUL|PLAYER` form; the module then falls back to detecting any visible Sunder. The fallback deliberately prefers avoiding repeated rage spending over insisting on ownership of the existing stack.

### Reactive-action readiness

Warrior Assist does not attempt to reproduce every Warrior restriction itself. Once the action slot is discovered, readiness uses the native action system:

- `HasAction()` where available;
- `IsUsableAction()`;
- `IsActionInRange()`;
- `GetActionCooldown()`.

This is especially important for Execute and Overpower windows. The current Smart Action baseline is accepted as working in normal use; this acceptance closes validation debt without asserting that every reactive branch was separately instrumented. The module does not automatically change stance or equipment to make an otherwise unusable action available; stance-aware intent handling remains a future feature, not a validation requirement.

### Safe Slam timing

With safe Slam enabled, Warrior Assist requires an explicit numeric swing-progress value and computes the no-clip window itself. The second runtime pass showed that none of the previously queried timer integrations exposed an active numeric value on the user's setup even while AttackBar visibly tracked the weapon swing. Warrior Assist therefore now owns a small internal main-hand tracker instead of depending on another addon's presentation state.

The internal tracker listens to the same WoW 1.12 self-combat message family used by the user-supplied AttackBar 5.0.7 source: ordinary `CHAT_MSG_COMBAT_SELF_HITS` / `CHAT_MSG_COMBAT_SELF_MISSES` white-swing messages reset the main-hand timestamp, while named spell messages are ignored except the Warrior on-next-swing replacements `Heroic Strike` and `Cleave`. `UnitAttackSpeed("player")` is captured at that reset and `GetTime()` provides numeric progress until the expected next swing. `PLAYER_LEAVE_COMBAT` clears the tracker. This is an independent OctoTweaks implementation; AttackBar is not a runtime dependency.

Swing progress is now resolved in this order:

1. Warrior Assist's internal combat-log main-hand tracker;
2. `CleveRoids.GetSwingPercentElapsed()` when SuperCleveRoidMacros can provide a numeric percentage;
3. SP_SwingTimer `st_timer` / `st_timerMax` globals;
4. an **active** `pfUI.swingtimer.mainhand` status bar.

The earlier prototype called `CleveRoids.ValidateNoSlamClip()` first and treated `false` as a definitive unsafe window. Runtime testing exposed that this can suppress Slam entirely because the same function returns false when no usable swing timer exists. The first correction switched to numeric external timers; the second runtime pass then established that those external timer states were not exposed on this client despite AttackBar functioning. The internal tracker removes that presentation/API dependency.

Slam cast time is resolved in this order:

1. SuperCleveRoidMacros `GetSpellCastTime("Slam")`, which derives effective tooltip timing;
2. ClassicAPI `C_Spell.GetSpellInfo(spellID).castTime`;
3. a 2.0-second fallback.

`/otwa slamcast <seconds>` sets a manual override and `/otwa slamcast auto` removes it. The previous 0.50-second prototype default is migrated away automatically.

The timing gate is intentionally allowed to be slightly permissive. Its condition is:

`elapsed <= (weapon speed - Slam cast time - safety margin + late tolerance) / weapon speed`.

`late tolerance` is extra start-window time in seconds. It does not make Slam autonomous; it only lets a manually triggered Smart Action accept some swing clipping instead of requiring a strict no-clip cast. The default is **0.30 s**. `/otwa slamtolerance 0` restores the strict window (subject to the safety margin), while values such as `0.30` or `0.50` progressively allow later Slam starts. The setting persists in `OctoTweaksDB.warriorAssist`.

`/otwa slamprobe` prints Slam readiness, rage/reserve state, resolved cast time/source, weapon speed, swing progress/source, the resulting timing-window decision including late tolerance, and the internal tracker's current age/duration/reset reason when active.

### Binding and commands

The ordinary WoW Key Bindings UI exposes **OctoTweaks Warrior Assist -> Smart combat action**.

The module also provides `/otwa`:

- `/otwa act` — invoke Smart Action manually from a slash command for diagnostics;
- `/otwa status` — print config, binding, last decision, discovered slots/ranks, and effective rage costs;
- `/otwa scan` — rebuild the native action-slot map then print status;
- `/otwa slamprobe` — print the complete Slam readiness/timing decision for runtime calibration;
- `/otwa debug on|off` — print each Smart Action decision/WAIT reason;
- `/otwa reserve <0-100>` — set the post-Sunder rage reserve;
- `/otwa ms <0-100>` — set the Mortal Strike overflow threshold;
- `/otwa toggle <action> on|off` — enable/disable a managed action;
- `/otwa cost <action> <0-100|auto>` — set/remove a rage-cost override;
- `/otwa slamsafe on|off` — enable/disable the timing gate;
- `/otwa slamcast <0-3|auto>` — set a manual Slam cast-time override or restore automatic resolution;
- `/otwa slammargin <0-1>` — set additional conservative Slam safety margin seconds;
- `/otwa slamtolerance <0-2>` — add allowed late-start time to the Slam window; alias `/otwa slamlate`; default 0.30 s;
- `/otwa bind <KEY>` / `/otwa unbind` — manage the native Smart Action binding;
- `/otwa reset` — restore Warrior Assist configuration defaults without clearing the key binding.

Action arguments accept normalized aliases such as `ms`, `mortalstrike`, `shout`, and `battleshout` in addition to the canonical internal names.

### Persistence

Feature-owned configuration is stored under `OctoTweaksDB.warriorAssist`:

- reserve/overflow rage thresholds;
- safe-Slam timing configuration, including persisted late-window tolerance;
- per-action enabled state;
- per-action rage-cost overrides;
- module-local debug flag.

The actual Smart Action key assignment is saved through WoW's native binding set and is not duplicated into SavedVariables.

### Compatibility and graceful degradation

The module compatibility probe requires:

- a Warrior player character;
- ClassicAPI `GetActionInfo` and `GetSpellInfo`;
- ClassicAPI `C_UnitAuras.GetAuraDataBySpellName`;
- native `IsUsableAction`, `GetActionCooldown`, and `UseAction`;
- basic combat unit APIs.

On a non-Warrior character or a client missing the required ClassicAPI surface, the module remains `WAITING`; unrelated OctoTweaks modules continue to load.

Warrior Assist now provides its own combat-log swing tracker, so pfUI, SP_SwingTimer, SuperCleveRoidMacros, and AttackBar are not required for Slam timing. The user confirmed this internal source successfully allows Slam on the tested 2.90 s weapon. The external timer integrations remain fallback sources. The current internal tracker is intentionally scoped to the user's 2H / one-hand-plus-shield use case; dual-wield main-hand/off-hand disambiguation is not yet claimed.

### Runtime observation — 2026-09-15

The first real-client pass confirmed:

- initial Sunder selection works;
- Battle Shout maintenance works;
- Mortal Strike overflow selection works;
- reserve-rage WAIT behavior and configured thresholds work.

The earlier staged tests confirmed Sunder, Battle Shout, Mortal Strike overflow, reserve preservation, configured thresholds, the internal combat-log swing tracker, and Slam selection on the tested 2.90 s weapon. On 2026-09-21 the user confirmed Warrior Assist works well and explicitly closed the module. That acceptance promotes the current baseline to runtime PASS without claiming separate instrumented observations for every reactive window. Slam late-window tolerance remains a user-tunable performance preference, not validation debt.

### Regression checklist for future Warrior Assist changes

For changes that plausibly affect combat selection/timing, re-check at minimum:

1. deploy the delta and confirm `/ot status` reports `wow.warrior_assist = ENABLED` on the Warrior;
2. place all six managed spells in native slots, run `/otwa scan`, and verify slots/ranks/costs;
3. confirm Smart Action does nothing out of combat/no target;
4. confirm one initial Sunder and no repeated Sunder once the aura is visible;
5. confirm missing Battle Shout maintenance with reserve preservation;
6. confirm low-rage Slam/MS are withheld below the 15-rage reserve;
7. confirm Overpower and Execute take priority when their native buttons become usable;
8. confirm high-rage Mortal Strike wins before Slam at the configured threshold;
9. validate Slam timing with `/otwa slamprobe` plus `/otwa debug on`; confirm the internal tracker advances across the swing and that `/otwa slamtolerance <seconds>` predictably widens/narrows the accepted start window;
10. move/change normal per-spell bindings and confirm Smart Action keeps working through slot rescans;
11. confirm every physical Smart Action press produces at most one action attempt.

Do not reopen the whole stable module for unrelated changes; revalidate only behavior plausibly affected by the change.
