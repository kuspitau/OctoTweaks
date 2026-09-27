# WoW / OctoWoW Client Features

## Scope

This target contains OctoTweaks features that depend on the WoW 1.12 / OctoWoW client itself rather than a third-party addon.

Use this file only as a router. Read the feature document for the module being changed; do not load both feature documents unless the task crosses both modules.

## Modules

- `wow.extra_action_bars` — 96 persistent virtual action slots, action assignment, native bindings, Quick Bind, layout and visibility behavior. Source: `OctoTweaks/modules/wow/ExtraActionBars.lua`. Documentation: `wow-extra-action-bars.md`.
- `wow.warrior_assist` — manually triggered Warrior Smart Action, native-slot discovery, rage policy, action priority and swing-aware Slam gating. Source: `OctoTweaks/modules/wow/WarriorAssist.lua`. Documentation: `wow-warrior-assist.md`.

## Shared client assumptions

- Target WoW 1.12 / OctoWoW and conservative Lua 5.0-era behavior.
- Prefer native client APIs and explicit compatibility probes over assumptions imported from later WoW versions.
- Native key assignments remain owned by the WoW binding system when the client already provides persistence.
- Current validation state belongs in `../CURRENT_STATE.md`; the feature docs contain reusable behavior, compatibility notes and regression procedures.
