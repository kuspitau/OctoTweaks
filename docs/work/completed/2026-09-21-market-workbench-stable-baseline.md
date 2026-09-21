# Market Workbench — stable baseline closure

## Objective

Close the last current Workbench validation issue on Aegis: Exchange 1.53.29: Similar Search refused some equipment subclasses when Aegis exposed no additional AH slot option.

## Current status

Work lifecycle: **COMPLETED**
Aegis 1.53.29 integration/hosted Workbench: **IN-GAME VALIDATION PASS by user acceptance (2026-09-21)**
Targeted slot-fallback correction: **IMPLEMENTED; STATIC VALIDATION PASS; IN-GAME VALIDATION PASS by user acceptance (2026-09-21)**

## Observed failure

Representative errors:

- `Similar search refused: AH equipment slot not resolved for: INVTYPE_2HWEAPON`
- `Similar search refused: AH equipment slot not resolved for: INVTYPE_RANGEDRIGHT`
- `Similar search refused: AH equipment slot not resolved for: INVTYPE_SHIELD`

Armor appeared to work normally; one-hand weapons should be rechecked as a regression control.

## Root cause / design decision

`Adapter:ResolveAuctionFilters()` previously required every non-empty target `equipLoc` to resolve to an entry returned by `AegisExchange.buy.SlotOptions(class, subclass)`. That assumption is too strict.

Aegis builds slot options from the client's `GetAuctionInvTypes(class, subclass)`. Some subclasses are already specific enough that this API exposes no additional slot dimension. Empty `SlotOptions` therefore means **no invType filter is needed**, not that the item is unsupported.

The correction keeps the safe behavior:

- exact class resolution remains mandatory;
- exact subclass resolution remains mandatory;
- if Aegis exposes slot options, exact localized slot resolution remains mandatory;
- if Aegis exposes zero slot options, `invType` stays nil and the query uses class + subclass.

Do not replace this with a hardcoded `INVTYPE_* -> AH slot index` table. Aegis/client category APIs remain the source of truth.

## Relevant files

- `OctoTweaks/modules/aegis/Adapter.lua`
- `OctoTweaks/modules/aegis/MarketWorkbench.lua`
- `docs/modules/aegis.md`
- `docs/CURRENT_STATE.md`
- `tests/README.md`

## Validation performed

- Aegis 1.53.29 source contract rechecked: its Buy engine treats `invType=nil` as no invType filter and obtains slot choices from `GetAuctionInvTypes`.
- Full repository `python tools/check.py`: expected PASS in the final delta validation.
- All addon Lua files: expected `texluac -p` PASS in the final delta validation.
- Focused adapter harness: verifies empty slot options return class/subclass with `invType=nil`, while non-empty slot lists still require/match the correct slot.

## Closure / runtime acceptance

The user confirmed after applying the slot fallback that Workbench works normally and the previously reported equipment-category errors no longer occur. This closes the targeted Similar Search validation debt.

The stable rule preserved by the implementation is:

- class/subclass resolution remains strict;
- when Aegis exposes AH slot options, Workbench still requires the exact localized slot;
- when Aegis exposes no AH slot options for that class/subclass, `invType=nil` is valid and the search proceeds without inventing a hardcoded slot mapping.

Any future regression should reopen only the affected behavior rather than downgrading the full Aegis/Workbench baseline.
