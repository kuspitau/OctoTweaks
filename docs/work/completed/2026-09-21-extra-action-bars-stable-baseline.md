# Extra Action Bars — completed stable-baseline record

## Objective

Add persistent virtual action bars to OctoTweaks so the user can keep substantially more action/qbind pairs than the native Blizzard action-slot layout exposes, with action-bar-like buttons and on-demand visibility.

## Final status

Work lifecycle: **COMPLETED / STABLE baseline accepted 2026-09-21**
Implementation: **ITERATION 6 IMPLEMENTED**
Static/desktop validation: **PASS in final repository validation**
OctoWoW in-game validation: **PASS by user acceptance**, including the current regular-macro path

## Runtime evidence received

The first in-game test confirmed:

- four default bars render in OctoWoW;
- spells can be dropped into virtual slots and their icons render.

The user also reported and illustrated:

- occupied icons appeared larger than the visible empty-slot outline;
- the apparent spacing between empty slots was misleadingly large;
- clicking empty slots could leave a blue pressed/hover-looking outline behind;
- clicking populated spell slots could leave a gold pressed outline behind;
- movement controls were not discoverable enough;
- a compact settings UI was desired.

## Iteration 2 changes

- replaced `UI-Quickslot2` slot shell with an exact-size one-pixel border;
- removed the native pushed/depressed texture entirely to prevent sticky pressed states;
- changed additive visual defaults to 30 px button size, 2 px icon inset, and 1 px spacing;
- added persisted global button-size, icon-inset, and slot-spacing settings;
- added a compact `OctoTweaks Action Bars` settings panel;
- settings can be opened by right-clicking `OTB` or `/otb config`;
- the `OTB` launcher moves with `Ctrl + drag` and `/otb ui` toggles its persisted visibility;
- panel exposes active bars, visual sizing, lock/unlock, quick bind, reset, selected-bar mode, columns, and scale;
- `Shift + Right Click` on `OTB` is now the lock/unlock shortcut;
- movement guidance explicitly points to the `OT1` / `OT2` drag handles;
- bar handles receive an elevated frame level for better visibility.

## Iteration 3 changes

- added Shift + left click internal move/swap for populated virtual actions;
- the source action remains in place until a destination is chosen, avoiding data loss if a move is abandoned;
- the selected source displays a controlled gold `M` marker;
- Shift + left click a different slot moves the action there, or swaps when the destination is occupied;
- Shift + left click the selected source again cancels;
- qbinds remain attached to logical slots rather than following moved actions;
- receiving an external cursor assignment cancels any pending internal move.

QuickLayout profile/qbind integration remains unimplemented pending inspection of the actual QuickLayout source/API.

## Relevant files

- `OctoTweaks/modules/wow/ExtraActionBars.lua`
- `OctoTweaks/Bindings.xml`
- `OctoTweaks/OctoTweaks.toc`
- `docs/modules/wow.md`
- `docs/CURRENT_STATE.md`

## Important implementation assumptions

- `Bindings.xml` is loaded by the WoW addon binding mechanism and is intentionally not a TOC source entry.
- Binding commands call stable logical slot functions rather than hidden button clicks.
- SuperMacro is optional; direct drag/drop of its private cursor representation is intentionally not assumed.
- The module does not hook or depend on pfUI internals.
- iteration-2 visual settings are additive SavedVariables fields; existing assignments and qbinds are preserved.
- internal action moves intentionally preserve slot identity: action content moves, qbind ownership does not.

## Remaining work

Retest the iteration-2 visual shell/settings panel plus iteration-3 action move/swap behavior. The authoritative checklist is in `docs/modules/wow.md`.

Do not mark the sticky-state or icon/border-size fixes as runtime PASS until the user confirms them in OctoWoW. Continue the wider action execution/binding/visibility validation only after the basic UI is stable.
## Iteration 4 follow-up

Runtime feedback after iteration 3 showed:

- Shift + left click could still execute the slot instead of entering the move/swap path;
- item drag/drop was not usable as expected for items such as a fishing pole.

Iteration 4 changes:

- captures Shift on the slot's `OnMouseDown` and consumes the corresponding left click before normal slot execution;
- suppresses the destination `OnClick` that can follow `OnReceiveDrag` on OctoWoW, so a dropped spell/item is not immediately cast/used;
- hardens item cursor parsing with id/link/name fallbacks;
- prefers concrete bag/equipment APIs when executing items, which is more reliable for equippable items;
- adds `/otb item <slot> <name/link/id>` as a fallback/manual assignment path.

Runtime validation remains **PENDING** for these iteration-4 changes.


## Iteration 5 follow-up

Runtime feedback after iteration 4 confirmed that item slots can now receive and use/equip items, but their icon rendered as a solid red square.

Iteration 5 changes:

- resolves item icons from the actual bag slot with `GetContainerItemInfo()` when possible;
- resolves equipped-item icons with `GetInventoryItemTexture()`;
- caches only non-empty string texture paths;
- rejects numeric/non-path `GetItemInfo()` or stale SavedVariables texture values before calling `SetTexture()`.

Runtime feedback now confirms that the item-icon rendering fix works in OctoWoW. Existing saved item slots self-heal when the item is present in bags/equipment because the concrete texture path is refreshed at runtime.

## Iteration 6 follow-up

Runtime feedback after iteration 5 confirmed the item path is working, but regular macros could not be assigned to OTBars like spells/items.

Iteration 6 changes:

- keeps regular macro assignments as first-class `macro` slot actions;
- accepts both numeric and string-like `GetCursorInfo()` macro tokens instead of requiring `tonumber()` to succeed;
- stores the observed `macroIndex` alongside the macro name, but only reuses that index while it still resolves to the same name;
- resolves numeric macro icon identifiers with `GetMacroIconInfo()` before passing them to `SetTexture()`;
- refreshes OTBar macro presentation on the Vanilla `UPDATE_MACROS` event;
- adds `/otb macro <slot> <name/index>` as a manual/fallback regular-macro assignment path;
- after runtime evidence showed the OctoWoW macro cursor token could map to the wrong macro, captures the source macro from `PickupMacro()` and uses the captured identity for OTBar drops; raw cursor-index handling is now fallback only;
- keeps qbind execution routed through `RunMacro` and preserves macro assignments through existing slot SavedVariables.

Focused desktop smoke coverage verifies numeric cursor tokens, string cursor tokens, numeric-icon resolution, and macro execution by stored slot. The user subsequently reported the current macro behavior appears correct and explicitly closed OTBars validation on 2026-09-21.


## Closure

This note is historical implementation/validation context. Current truth is `docs/CURRENT_STATE.md` and `docs/modules/wow.md`. Future enhancements do not reopen this baseline unless they change affected runtime behavior.
