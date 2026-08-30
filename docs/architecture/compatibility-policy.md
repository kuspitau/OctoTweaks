# Compatibility Policy

## Runtime baseline

OctoTweaks targets WoW 1.12 / OctoWoW and should use conservative Lua compatible with that environment.

## Version knowledge

There are two different claims:

- **tested version** — a human/agent has actually validated the module against that target version;
- **structurally compatible** — the runtime probe found the symbols/shape required by the module.

Do not conflate them.

A structural probe may allow a module to operate on an untested version, but diagnostics/documentation should preserve the fact that runtime validation is missing.

## Graceful degradation

Missing target addons or missing expected internals must not break OctoTweaks globally.

Prefer `WAITING`/local disablement over a hard error.

## New external dependencies

If a module requires SuperWoW or another non-addon client extension, document that requirement in both the module source header and target documentation.
