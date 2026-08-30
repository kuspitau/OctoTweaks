# Roadmap

This file contains future intentions only. It is not authoritative for current implementation status.

## Near term

- Execute and validate root `addon_update.bat` on the user's Windows/OctoWoW installation.
- Validate the bootstrap in the real OctoWoW client.
- Validate `pfui.libpredict_fix` against the gathering/mining reproduction.
- Add module enable/disable commands only if useful after first runtime testing.
- Design the first configurable pfUI nameplate extension when requirements are ready.

## Candidate future modules

### pfUI

- friendly NPC vs friendly player nameplate behavior;
- nameplate text controls;
- other OctoWoW/SuperWoW compatibility fixes discovered in use.

### pfQuest

- target-specific fixes/extensions as concrete needs are identified.

### Aegis Exchange

- target-specific fixes/extensions as concrete needs are identified.

## Deferred architecture

Do not implement these until a real requirement justifies them:

- configuration UI;
- SavedVariables migrations;
- shared hook manager more complex than current wrappers;
- dependency graph between modules;
- automated in-client test harness.
