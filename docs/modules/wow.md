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
In-game validation: **PARTIAL; item path confirmed, regular-macro drag/drop retest required after iteration 6**

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
- spells can be dragged onto virtual slots and their icons appear.

The same test exposed two visual issues in the first prototype:

1. the native `UI-Quickslot2` texture has visual padding, so the visible empty-slot outline looked materially smaller than the actual button/icon area;
2. the native pushed-state texture could remain visible after clicking a slot, producing persistent blue/gold outlines.

Iteration 2 removes both native textures from the slot shell. Slots now use an exact-size one-pixel border and no persistent pushed texture. This correction still requires in-game retesting.

The next runtime test found two interaction problems: Shift + left click could reach normal slot execution instead of the internal move path, and dropping an item could be followed by a destination click that immediately used/equipped the just-assigned item. Iteration 4 records Shift at mouse-down time and suppresses the post-drop click. Item assignment is also hardened for equippable items and item-link/id resolution. These corrections are implemented but still require OctoWoW retesting.

A later runtime test confirmed that item assignment/use works, including equippable items, but item icons rendered as a solid red square. Iteration 5 treats this as an icon-resolution compatibility issue: item textures are resolved from the concrete bag slot via `GetContainerItemInfo()` or equipped slot via `GetInventoryItemTexture()` first. `GetItemInfo()` and stored texture values are accepted only when they are non-empty strings, preventing numeric/non-path values from being passed to `SetTexture()`. The user subsequently confirmed that the corrected item icons render properly in OctoWoW.

Regular macro drag/drop is supported, but OctoWoW runtime testing exposed that the numeric token observed from `GetCursorInfo()` is not a reliable macro index for every macro (observed examples included macro 1 resolving as 2, macro 2 as 4, and macro 4 as unavailable index 5). OTBar therefore captures the authoritative macro identity from the public `PickupMacro()` call at drag start and uses that captured action at drop time when it matches the current macro cursor. The raw cursor token remains only a fallback for code paths that do not call `PickupMacro()`. OTBar stores both macro name and resolved index, resolves numeric macro-icon identifiers through `GetMacroIconInfo()`, refreshes on `UPDATE_MACROS`, and provides `/otb macro <slot> <name/index>` as a manual fallback. Runtime validation of this correction remains pending.

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

Current limitations pending runtime iteration:

- the new settings panel is custom OctoTweaks UI rather than pfUI's own configuration framework;
- range coloring and generic `IsUsableAction`-style state are not available for every virtual action type;
- direct spell and item cooldowns are displayed, but arbitrary macro/SuperMacro cooldown inference is not attempted;
- direct SuperMacro drag/drop is not implemented; use `/otb super`;
- dragging an already-populated Blizzard action-button slot as cursor type `action` is not yet imported;
- assignments are persistent but there is no profile layer or QuickLayout profile integration yet;
- the 96-slot maximum remains fixed so stable binding command names can be declared statically.

### Required in-game retest after iteration 4

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
