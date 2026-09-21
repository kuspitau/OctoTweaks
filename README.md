# OctoTweaks

OctoTweaks is a modular compatibility/fix/feature addon for WoW 1.12 on OctoWoW. It extends or patches other addons externally while keeping their installed source untouched.

## Current modules

- `pfui.libpredict_fix` — guards pfUI prediction handling against incomplete player cast timestamps.
- `wow.extra_action_bars` — 96 persistent virtual action slots with configurable bars, items/spells/macros, native bindings, quick-bind mode, and configurable visibility.
- `wow.warrior_assist` — manually triggered Warrior Smart Action with configurable rage policy, action priority, diagnostics, and swing-aware Slam gating.
- `aegis.integration` — capability-probed compatibility boundary around Aegis: Exchange internals.
- `aegis.market_workbench` — Target/Reference search, pricing, and Aegis-backed posting workflow.
- `aegis.market_workbench_ui` — externally hosted Workbench sub-tab inside exact source-audited Aegis UI versions, with standalone fallback.

Current state and known issues are authoritative in `docs/CURRENT_STATE.md`.

## Local repository workflow

The local repository is the development source of truth. Conversation agents normally deliver repository-relative delta ZIPs; extract them over repository root, run any included temporary deletion helper when required, validate, deploy/test, then commit/push once accepted.

See `AGENTS.md` and `docs/architecture/delta-delivery-policy.md`.

## Deploy current local addon to OctoWoW

From repository root, double-click `addon_update.bat`. Default game root: `C:\Games\OctoWow`.

The script validates first, removes the previous deployed OctoTweaks directory, copies the repository addon, and verifies `OctoTweaks.toc`. An alternate game root may be passed as the first argument.

## Manual install / distribution

The repository `OctoTweaks/` directory is the addon source. Build a clean distribution with:

```text
python tools/package.py
```

or `tools\package.bat`. Output is written under `dist/`.

## Useful in-game commands

- `/ot status` / `/ot modules` — module state.
- `/ot debug on|off` — core diagnostics.
- `/otb config` — Extra Action Bars settings; `/otb` shows subsystem help.
- `/otwa status` — Warrior Assist diagnostics/configuration.
- `/otaegis probe` — Aegis capability/version diagnostics.
- `/otmarket` — open/select Market Workbench; `/otmarket status` prints Workbench/Aegis UI state.

Subsystem docs contain complete command sets.

## Developer validation

Run `python tools/check.py` (or `tools\check.bat`).

## Repository navigation

Agents and contributors should start with `AGENTS.md`, then `docs/CURRENT_STATE.md` and `docs/INDEX.md`.

## License

No license has been selected yet. Add one deliberately before treating the repository as an open-source distribution.
