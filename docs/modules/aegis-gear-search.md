# Aegis Gear Search

## Status

Module: `aegis.gear_search`  
Target: Aegis: Exchange 1.53.29 on WoW 1.12 / OctoWoW  
Implementation: **IMPLEMENTED**  
In-game validation: **PASS by user acceptance (2026-09-27)**

The current baseline includes Slot/Type metadata fallbacks, target-slot filtering, generic per-stat Show/Min/Weight configuration, dynamic sortable stat columns, named presets, and coexistence with Market Workbench through the shared Aegis UI extension registry. The private UI seam remains exact-version-gated by `aegis.integration`.

## Purpose

Gear Search adds a numerical equipment-search layer above Aegis without modifying Aegis source files. Aegis remains responsible for Auction House query pacing and page traversal. OctoTweaks owns category composition, listing reduction, tooltip stat parsing, local slot/stat/price filters, weighted scoring, sorting, presets, persistence, and presentation.

Entry points:

```text
/otgear
/otgear search
/otgear stop
/otgear reset
/otgear status
/otgear presets
/otgear save <name>
/otgear load <name>
/otgear delete <name>
```

The feature is hosted as a separate `Gear Search` Aegis sub-tab. It intentionally does **not** auto-buy or post auctions.

## Files and boundaries

- `modules/aegis/UIExtensions.lua` — shared multi-extension Aegis UI registry used by Workbench and Gear Search.
- `modules/aegis/GearSearchAdapter.lua` — Gear Search access to Aegis Buy category helpers and the paced scanner.
- `modules/aegis/GearSearch.lua` — settings/schema migration, UI, presets, search orchestration, tooltip parser, local filters, ranking/sorting, diagnostics, and module registration.

Higher-level Gear Search code does not reach directly into `AegisExchange.*`.

## Search categories

Supported independently selected categories:

- Cloth;
- Leather;
- Mail;
- Plate;
- Shields;
- Armor/Miscellaneous;
- Weapons.

Armor selections resolve one Aegis class/subclass query each. `Weapons` expands to weapon subclasses exposed by Aegis/`GetAuctionItemSubClasses`, so it may require several paced category queries. `GearSearchAdapter.lua` deduplicates class/subclass tuples; Aegis still owns throttle, retries, page traversal, and query timing.

## Slot filter and metadata fallback

Supported local slot groups include Head, Neck, Shoulders, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Finger, Trinket, One-hand, Two-hand, Main hand, Off hand, Shield, Held offhand, Ranged, Relic, and Any slot. Chest groups `INVTYPE_CHEST`/`INVTYPE_ROBE`; Ranged groups common ranged equipment-location variants.

Slot filtering is applied locally after the Aegis scan. A real-client cold-cache failure established an important compatibility invariant: auction tooltips can be readable before `GetItemInfo` exposes enough metadata. Current metadata resolution therefore uses layered fallbacks:

1. normalized `Aegis:GetItemInfo` from the exact auction link;
2. normalized metadata from the base item id;
3. Aegis-resolved scan class/subclass names carried on the result as a Type fallback;
4. exact equipment-location inference from the readable tooltip line, including localized `INVTYPE_*` labels.

This fallback path is part of the accepted runtime baseline. Slot filtering still does not reduce server-side page count.

## Variant reduction

A category sweep may return repeated auctions for the same item variant. Gear Search reduces rows before tooltip parsing:

- key = item id + enchant id + random-property id;
- per-instance unique id is ignored;
- the cheapest unit-buyout listing for that variant is retained;
- minimum quality and maximum price are applied before tooltip parsing.

This preserves suffix-specific stats while keeping tooltip work bounded.

## Tooltip parser and generic stat model

Parsing runs after the paced AH scan through a hidden `GameTooltip`, in small batches (3 item variants per frame by default).

Scoreable fields are:

- effective Heal;
- generic spell power (`SP`, damage + healing);
- MP5;
- Intellect, Spirit, Stamina, Strength, Agility;
- attack power and ranged attack power;
- physical Hit and Crit;
- spell Hit and spell Crit;
- Defense, Dodge, Parry, Block chance, Block Value;
- Armor.

`Heal` means pure healing bonus + generic damage-and-healing spell power. `SP` is the generic damage-and-healing contribution alone. A healer profile normally weights Heal and leaves SP at zero; a caster-DPS profile can do the inverse. Weighting both intentionally double-values generic spell power.

The parser uses explicit English Vanilla-style sentence patterns and common compact `+N Stat` forms. It does not guess unknown wording.

Not yet modeled independently: school-specific spell damage, resistances, weapon DPS/speed, proc/on-use effects, set bonuses, sockets, or post-Vanilla stat systems.

## Filters, stat configuration and score

Persistent state lives under `OctoTweaksDB.gearSearch`. Current schema is **3**; older supported settings/presets migrate additively.

Coarse controls include selected categories, slot filter, min/max item level, minimum quality (`0`–`6`), maximum unit buyout in gold (`0` = unlimited), and minimum total score.

`STATS...` opens the per-stat editor. Every parsed stat has independent controls:

- **Show** — expose it as a sortable result column (maximum eight at once);
- **Min** — reject an item below this parsed value (`0` disables the minimum);
- **Weight** — contribution to Score (`0` removes it from Score).

A hidden stat may still affect score or filtering. A shown stat may have zero weight. Score is the sum of `stat * weight` across the registry.

The built-in Resto Shaman heuristic remains editable rather than being a class rule:

```text
Heal       1.00
MP5        8.00
Intellect  0.70
Spirit     0.15
Stamina    0.10
Spell crit 12.00
all other weights 0
```

Its default view shows Heal, MP5, Intellect, Spirit, Stamina and spell Crit.

## Presets

Named presets persist category selections, slot selection, level/quality/price filters, minimum total score, every per-stat minimum, every stat weight, and the visible stat columns.

Built-ins are `Resto Shaman` and `Blank`. Supported older presets are migrated by reconstructing their dedicated minima and previous implicit visible-column choices.

## Sortable result table

Always-visible columns are Score, Price, Slot, Type and Item. Up to eight selected stat columns appear between Score and Price. Column positions are recalculated from the visible-stat count, giving Item more room when fewer stats are shown.

Every visible header is clickable. Re-clicking the active header reverses direction. Numeric stat/score columns default to descending; Price/Slot/Type/Item default to ascending. Sort choice persists. Hiding the currently sorted stat falls back to Score. Item names use quality color when available.

## UI and ownership behavior

The main screen keeps the dense stat matrix out of the default view: `STATS...` opens a compact overlay with two columns of Show/Min/Weight rows. Attempting to show a ninth stat is refused immediately. `APPLY` commits the editor values locally; `CANCEL` restores persisted values. Search/preset-save paths also read the editor so un-applied edits are not silently discarded.

Switching away or closing the AH stops only Gear Search-owned scan/parsing work. It does not cancel unrelated Aegis jobs. Gear-search queries participate in the shared Aegis/OctoTweaks query-owner guard as `gear_search`.

## Current limitations

- Slot filtering is post-scan/local and does not reduce Aegis pages requested.
- `Weapons` scans every exposed weapon subclass and can be slower than one armor-subclass search.
- Armor/Miscellaneous ring/neck/trinket availability depends on the realm/client AH subclass mapping.
- Result stat columns are limited to eight at once; hidden stats may still filter/score.
- English-style tooltip wording is the parser baseline; unknown text is not guessed.
- No price-per-score, equipped-item comparison, school-specific spell damage/resistances, weapon DPS/speed scoring, proc/on-use evaluation, or direct Buy action.

## Regression procedure

Use this checklist only when a future change plausibly affects Gear Search:

1. Open AH on a source-audited Aegis version and confirm Workbench + Gear Search attach once.
2. Run a broad armor search; verify Type and Slot resolve even for cold-cache items.
3. Exercise at least two slot filters and confirm displayed results match the target slot.
4. Change Show/Min/Weight independently; verify columns, filtering and Score react as intended.
5. Save a preset, load another, then reload it; verify filters plus Show/Min/Weight round-trip.
6. Verify Score/Price/visible-stat sorting and direction reversal; hide the sorted stat and confirm Score fallback.
7. If category logic changed, exercise the affected Plate/Shield/Weapon or miscellaneous path.
8. Switch Gear Search → Workbench → Buy → Gear Search and confirm shared-registry coexistence and ownership cleanup.
9. On failure, capture the Lua error plus `/otgear status` and relevant `/otaegis probe` output.

## Candidate follow-ups

- server-side slot narrowing where Aegis `SlotOptions` is trustworthy;
- school-specific spell damage and resistances;
- weapon DPS/speed scoring;
- equipped-item comparison / upgrade delta;
- price-per-score / budget-efficiency sorting;
- richer preset browser if preset count grows.
