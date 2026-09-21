# Current State

Last reviewed: 2026-09-21

This document is the compact dashboard of what is true now. Detailed implementation knowledge and reusable validation procedures belong in the module docs; historical task detail belongs in `docs/work/completed/`; future work belongs in `ROADMAP.md`.

State/validation vocabulary is defined in `docs/architecture/documentation-policy.md`.

## Environment and workflow

- Game/API baseline: WoW 1.12 / OctoWoW.
- Lua baseline: conservative Lua 5.0-era compatibility.
- The user's local repository is the active development source of truth.
- Conversation-agent changes are normally delivered as repository-relative delta ZIPs, tested locally, then committed/pushed once accepted.
- `addon_update.bat` validates before replacing the deployed addon. Its exact Windows script path is not separately certified here; routine in-game use confirms the addon/bootstrap itself is operational.
- Full repository `python tools/check.py`: **PASS** on the state produced by this delta (2026-09-21).

## Core

State: **STABLE**
Implementation: **IMPLEMENTED**
Runtime: **PASS through routine OctoTweaks use**

The bootstrap, SavedVariables initialization, module registry/isolation, compatibility probes, retry lifecycle, `/ot` diagnostics, static checker, package builder, and clean deployment script are established baseline infrastructure.

## Module dashboard

| Module | State | Runtime baseline | Current open issue |
| --- | --- | --- | --- |
| `pfui.libpredict_fix` | **STABLE** | pfUI 5.5.4 / OctoWoW; user reports the historical error has not recurred over extended normal use | None currently known |
| `wow.extra_action_bars` | **STABLE** | OctoWoW; spells/items/icons/move-swap and current regular-macro path accepted by user | Future enhancements only |
| `wow.warrior_assist` | **STABLE** | Current OctoWoW Warrior setup; user confirms the Smart Action works and closes validation | Tuning remains configurable, not validation debt |
| `aegis.integration` | **STABLE** | Aegis: Exchange 1.53.29 (`924ce71f...`) runtime-confirmed; 1.20.2 retained as historical runtime baseline | Unknown Aegis versions still fail/diagnose conservatively |
| `aegis.market_workbench_ui` | **STABLE** | Hosted Workbench works with current Aegis 1.53.29 | Exact private-UI versions remain source-audit gated |
| `aegis.market_workbench` | **STABLE** | Aegis 1.53.29; Target → Similar Search → Reference → Suggested Price → POST plus slotless-category fallback accepted in game | None currently known |

## Known limitations (not validation debt)

- No repository-wide configuration UI; feature-specific UIs exist where needed.
- Module enable overrides exist in SavedVariables but no general public enable/disable command is exposed.
- No repository-wide SavedVariables migration framework; feature-owned additive schemas are used where required.
- No automated real-client WoW harness; runtime acceptance remains manual.
- Extra Action Bars intentionally does not yet provide generic range/usability tinting, direct SuperMacro drag/drop, or QuickLayout/profile integration.
- Warrior Assist's internal swing tracker is intended for the current 2H / one-hand-plus-shield use case; dual-wield disambiguation is not claimed.
- Workbench future features such as `POST + NEXT`, guarded smart-reference policies, fee/deposit-aware economics, inventory analytics, background scanning, freshness UI, and deeper analytics are roadmap items, not current validation failures.
