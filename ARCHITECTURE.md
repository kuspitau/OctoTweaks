# OctoTweaks Architecture

## Goal

OctoTweaks is one installed addon containing many independent tweaks. It should remain maintainable as modules are added for different target addons and as independent conversation agents contribute successive local deltas.

## Design principles

1. **External modification** — do not maintain modified third-party addon files.
2. **Module isolation** — one broken/unavailable tweak should not disable unrelated tweaks.
3. **Compatibility probing** — verify required structures before applying version-sensitive hooks.
4. **Small core** — keep target-specific logic out of the core.
5. **Explicit state** — module runtime status and documentation status must be inspectable.
6. **Conservative client compatibility** — prefer WoW 1.12/Lua 5.0-compatible constructs.
7. **Progressive architecture** — add shared abstractions only when multiple real modules justify them.
8. **Local source of truth** — the user's local repository may be ahead of GitHub while deltas are being tested; GitHub is not assumed to be the live working state.
9. **Clean deployment** — the installed addon is a disposable deployment copy of repository `OctoTweaks/`, recreated by root `addon_update.bat`.

## Runtime layout

`Core.lua` creates the global `OctoTweaks` object, initializes SavedVariables, and owns the event frame.

`core/Compatibility.lua` contains small client/version compatibility helpers.

`core/Modules.lua` owns module registration, probes, activation, and runtime state.

`core/Diagnostics.lua` exposes `/ot` diagnostics.

`modules/<target>/` contains target-specific modules.

## Module lifecycle

A module is registered during addon file loading.

At initialization and relevant addon-load events, the core:

1. checks configuration;
2. runs the module compatibility probe;
3. leaves the module `WAITING` if its target/structure is unavailable;
4. calls `enable()` if the probe passes;
5. records `ENABLED` or `ERROR` without aborting other modules.

Current runtime states are intentionally simple:

- `REGISTERED`
- `WAITING`
- `DISABLED`
- `ENABLED`
- `ERROR`

These runtime states are separate from documentation/work states such as planned, experimental, or runtime-validation-pending.

## SavedVariables

`OctoTweaksDB` currently stores:

- `debug`
- per-module enable overrides under `modules`

No migration framework exists yet. Introduce one only when a real schema change requires it, and record the decision.

## Local delta workflow

Conversation agents normally deliver repository-relative delta archives rather than modifying GitHub directly. The user's local repository can therefore be newer than the remote repository until runtime validation succeeds.

The handoff contract is defined in `docs/architecture/delta-delivery-policy.md`.

## Local game deployment

The root `addon_update.bat` is the canonical development deployment path. It validates first, deletes the previous deployed addon directory, then copies the repository's current `OctoTweaks/` folder into the OctoWoW AddOns directory.

This delete-then-copy rule prevents removed or renamed source files from surviving in the game installation.

## Hooking policy

See `docs/architecture/hooking-policy.md`.

## Documentation model

See `docs/architecture/documentation-policy.md`.
