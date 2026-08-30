# Module System

## Purpose

Keep independent tweaks isolated while allowing one installed addon to host many target-specific patches and features.

## Minimal module contract

A module is a table registered with `OctoTweaks:RegisterModule(module)`.

Required:

- `id`
- `enable()`

Recommended:

- `category`
- `target`
- `defaultEnabled`
- `testedVersion` or equivalent version notes
- `probe()` when touching external structures

## Probe behavior

`probe()` returns:

- `true, reason` when activation is structurally safe;
- `false, reason` when prerequisites are not currently satisfied.

A failed probe is `WAITING`, not a fatal addon error. The core may retry after later addon-load events.

A thrown probe error becomes module state `ERROR` but must not abort unrelated modules.

## Enable behavior

`enable()` should be idempotent whenever practical.

Return:

- `true, reason` (or no explicit false) on success;
- `false, reason` on controlled refusal.

Unexpected Lua errors are caught by the core and recorded as `ERROR`.

## Disable behavior

Runtime disable/unhook is not part of the initial contract. Add it only when a real use case requires safe reversible hooks.

## Shared abstractions

Do not add a generalized event bus, dependency graph, hook manager, or object framework merely because future modules might need one. Introduce shared machinery when at least two concrete modules demonstrate the requirement.
