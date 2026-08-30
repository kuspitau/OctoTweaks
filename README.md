# OctoTweaks

OctoTweaks is a modular compatibility/fix/feature addon for WoW 1.12 on OctoWoW. It extends or patches other addons externally while keeping their installed source untouched.

## Initial scope

The bootstrap currently contains one real module:

- `pfui.libpredict_fix` — guards pfUI's prediction handler against incomplete `UnitCastingInfo("player")` timestamps observed on OctoWoW/SuperWoW-style spellcast events.

Future modules can target pfUI, pfQuest, Aegis Exchange, or other addons without turning OctoTweaks into a monolithic patch file.

## Local repository workflow

The local repository is the development source of truth. Conversation agents normally deliver repository-relative `delta_changes.zip` archives; the user extracts them over the local repository, applies any required `delete_files.bat`, validates, deploys to the game, tests, then commits/pushes only once stable.

See:

- `AGENTS.md`
- `docs/architecture/delta-delivery-policy.md`

## Deploy current local addon to OctoWoW

From repository root, double-click:

`addon_update.bat`

Default game root:

`C:\Games\OctoWow`

The script:

1. validates the repository first;
2. leaves the installed addon untouched if validation fails;
3. removes the previous `Interface\AddOns\OctoTweaks` deployment completely;
4. copies the current repository `OctoTweaks\` directory into the game;
5. verifies that `OctoTweaks.toc` exists after deployment.

You can override the game root from a command prompt:

`addon_update.bat "D:\Games\OctoWow"`

## Manual install / distribution

The repository's `OctoTweaks/` directory is the actual addon source. A clean distribution ZIP can be built with:

```text
python tools/package.py
```

or:

`tools\package.bat`

The package is written under `dist/`.

## Useful in-game commands

- `/ot status`
- `/ot modules`
- `/ot debug on`
- `/ot debug off`

## Developer validation

Run:

```text
python tools/check.py
```

or:

`tools\check.bat`

## Repository navigation

Agents and contributors should start with `AGENTS.md`, then `docs/CURRENT_STATE.md` and `docs/INDEX.md`.

## License

No license has been selected yet. Add one deliberately before treating the repository as an open-source distribution.
