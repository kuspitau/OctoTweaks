# Current State

Last reviewed: 2026-09-27

This is the compact dashboard of what is true now. Reusable implementation/validation detail belongs in the owning module docs; historical task detail belongs in `docs/work/completed/`; future work belongs in `ROADMAP.md`.

State/validation vocabulary is defined in `docs/architecture/documentation-policy.md`.

## Environment and workflow

- Game/API baseline: WoW 1.12 / OctoWoW.
- Lua baseline: conservative Lua 5.0-era compatibility.
- The user's local repository is the active development source of truth; conversation-agent changes are normally applied as repository-relative deltas and committed after local acceptance.
- `addon_update.bat` validates before replacing the deployed addon.
- Last full-repository `python tools/check.py`: **PASS on 2026-09-27** for the current local snapshot.

## Core

State: **STABLE**  
Implementation: **IMPLEMENTED**  
Runtime: **PASS through routine OctoTweaks use**

The bootstrap, SavedVariables initialization, module registry/isolation, compatibility probes, retry lifecycle, `/ot` diagnostics, static checker, package builder, and clean deployment script are established baseline infrastructure.

## Module dashboard

| Module | State | Runtime baseline | Current issue |
| --- | --- | --- | --- |
| `pfui.libpredict_fix` | **STABLE** | pfUI 5.5.4 / OctoWoW; historical prediction error has not recurred in extended normal use | None known |
| `wow.extra_action_bars` | **STABLE** | Current OctoWoW; spell/item/macro assignment, movement, bindings and current UI accepted by user | Future enhancements only |
| `wow.warrior_assist` | **STABLE** | Current OctoWoW Warrior setup; Smart Action accepted by user | Tuning remains configurable, not validation debt |
| `aegis.integration` | **STABLE** | Aegis 1.53.29 (`924ce71f...`); backend and shared multi-extension UI registry accepted in game | Exact-version private UI gate remains intentional |
| `aegis.market_workbench` | **STABLE** | Aegis 1.53.29; Target → Similar Search → Reference → Suggested Price → POST and slotless-category fallback accepted in game | Future pricing/economics features only |
| `aegis.market_workbench_ui` | **STABLE** | Hosted Workbench on Aegis 1.53.29, including coexistence through the shared extension registry, accepted by user | None known |
| `aegis.gear_search` | **STABLE** | Current Aegis 1.53.29 Gear Search, including Slot/Type fallbacks, generic stat configuration, sorting and presets, accepted by user on 2026-09-27 | Future enhancements only |

## Known limitations

- No repository-wide configuration UI; feature-specific UIs exist where needed.
- Module enable overrides exist in SavedVariables but no general public enable/disable command is exposed.
- No repository-wide SavedVariables migration framework; feature-owned additive schemas are used where required.
- No automated real-client WoW harness; runtime acceptance remains manual.
- Extra Action Bars intentionally does not yet provide generic range/usability tinting, direct SuperMacro drag/drop, or QuickLayout/profile integration.
- Warrior Assist's internal swing tracker targets the current 2H / one-hand-plus-shield use case; dual-wield disambiguation is not claimed.
- Gear Search uses English-style tooltip parsing, local/post-scan slot filtering, a maximum of eight visible stat columns, and does not yet model school-specific spell damage, resistances, weapon DPS/speed, procs/on-use effects, set bonuses, or equipped-item upgrade deltas.
- Gear Search groups auction listings by item id + enchant id + random-property id and retains the cheapest listing for that variant; the per-instance unique id is intentionally ignored.
- Workbench safeguards such as guarded smart-reference policies, `POST + NEXT`, fee/deposit-aware economics, inventory analytics, freshness UI, background scanning, and deeper analytics remain roadmap items.
