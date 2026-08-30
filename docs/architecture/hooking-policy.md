# External Hooking Policy

## Default preference order

1. target addon's documented/public extension API;
2. callback/event extension point;
3. wrapper around an exposed function/frame script;
4. targeted replacement of an exposed function with preserved delegation;
5. invasive workaround only when no reasonable external alternative exists.

## Requirements for version-sensitive hooks

A module that depends on third-party internals must:

- document the exact symbol/frame/function relied upon;
- perform a structural probe before activation;
- fail locally if the structure is absent;
- record the tested target version in source/docs when meaningful;
- avoid claiming compatibility with untested versions solely because the probe passes.

## Forbidden default approach

Do not patch files inside `Interface/AddOns/<third-party-addon>/` as OctoTweaks' normal installation mechanism.

Do not vendor a modified copy of a third-party addon merely to change a small behavior.

If external patching truly cannot satisfy a requirement, document the limitation and make a deliberate architecture decision before introducing an exception.
