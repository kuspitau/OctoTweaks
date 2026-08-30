# Current State

Last reviewed: 2026-08-30

This document describes what is true in the repository now. Do not put speculative future work here.

## Development/handoff workflow

Status: **DEFINED**

Current source-of-truth workflow:

- the user's local repository is the active development state;
- conversation agents normally return `delta_changes.zip` rather than editing GitHub directly;
- deltas are extracted over repository root;
- file deletions/renames are handled by a temporary `delete_files.bat` when required;
- read-only local path discovery can use temporary `get_paths.bat` when required;
- temporary handoff helpers and `delta_changes.zip` are ignored by Git;
- root `addon_update.bat` validates and cleanly redeploys the current repository addon into OctoWoW;
- the user tests locally before committing/pushing stable state to GitHub.

Static validation of this workflow's repository files: **PASS** (`python tools/check.py`, 2026-08-30).
Windows runtime execution of `addon_update.bat`: **PENDING**.

## Environment target

- Game/API baseline: WoW 1.12 / OctoWoW
- Lua baseline: conservative Lua 5.0-era compatibility
- Optional ecosystem: SuperWoW and third-party addons as required per module

## Core

Status: **IMPLEMENTED**

Implemented:

- global OctoTweaks bootstrap;
- SavedVariables initialization (`OctoTweaksDB`);
- module registration and isolated activation;
- compatibility probes;
- runtime states (`REGISTERED`, `WAITING`, `DISABLED`, `ENABLED`, `ERROR`);
- retry on addon-load/login events;
- `/ot` diagnostic commands;
- static repository checker;
- package builder;
- clean local deployment script at repository root.

Static/desktop validation: **PASS** (`python tools/check.py`, 2026-08-30).
In-game validation: **PENDING**.

## Module catalog

### `pfui.libpredict_fix`

Category: compatibility  
Target: pfUI  
Reference version: pfUI 5.5.4  
Default: enabled  
Implementation: **IMPLEMENTED**  
Static/desktop validation: **PASS** (`python tools/check.py`, 2026-08-30)  
In-game validation: **PENDING**

Purpose:

Prevent pfUI `libs/libpredict.lua` from attempting arithmetic on missing cast timestamps when its named `pfPredictionSender` frame receives an incomplete `UNIT_SPELLCAST_START` state.

Implementation strategy:

- external wrapper around `pfPredictionSender`'s existing `OnEvent` handler;
- only suppresses the problematic player spellcast-start event when `starttime` or `endtime` is not numeric;
- delegates all other events/states to the original handler;
- does not modify pfUI files.

Required runtime test:

1. deploy with root `addon_update.bat`;
2. enable pfUI and OctoTweaks;
3. run `/ot status` and confirm `pfui.libpredict_fix = ENABLED`;
4. reproduce mining/gathering that previously caused the `endtime` nil error;
5. verify no Lua error occurs;
6. verify ordinary player casts still behave normally;
7. optionally enable `/ot debug on` and confirm malformed cast events are reported when reproduced.

## Known limitations

- No configuration UI yet.
- Module enable overrides exist in SavedVariables but no public enable/disable slash command is exposed yet.
- No SavedVariables migration framework yet.
- No automated WoW runtime harness; in-game behavior must be validated manually.
- `addon_update.bat` has not yet been executed on the user's Windows installation.
- Only pfUI has a target-specific module/document so far.
