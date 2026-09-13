# Roadmap

This file contains future intentions only. It is not authoritative for current implementation status.

## Near term

- Execute and validate root `addon_update.bat` on the user's Windows/OctoWoW installation.
- Validate the bootstrap in the real OctoWoW client.
- Validate `pfui.libpredict_fix` against the gathering/mining reproduction.
- Add module enable/disable commands only if useful after first runtime testing.
- Design the first configurable pfUI nameplate extension when requirements are ready.
- Integrate the now runtime-validated Market Workbench presentation into the Aegis UI without modifying third-party files, preserving the phase-1 Target → Similar Search → SET → POST workflow.

## Candidate future modules

### pfUI

- friendly NPC vs friendly player nameplate behavior;
- nameplate text controls;
- other OctoWoW/SuperWoW compatibility fixes discovered in use.

### pfQuest

- target-specific fixes/extensions as concrete needs are identified.

### Aegis Exchange / Market Workbench

Phase 1 (Target → Similar Search/poll → tooltip → SET → Suggested Price → POST) is runtime-validated on Aegis 1.20.2. Candidate increments are:

- integrate the Workbench as an Aegis-native-feeling sub-tab/panel from OctoTweaks, with probes around all private Aegis UI structures used;
- `POST + NEXT` using Aegis' existing bag/posting workflow where possible;
- reference policies: Manual, Exact-first, Auto floor, then guarded Smart reference;
- expanded sell economics: deposit, AH net, vendor comparison and margin;
- sortable inventory market view built from Aegis market/vendor data;
- tooltip vendor-margin additions using already-known data only;
- explicit freshness display when a stable Aegis accessor/representation has been identified;
- idle/background scanning policy only after query contention and priority behavior are validated in OctoWoW;
- deeper analytics (history/distribution/depth/spreads) with observed facts kept distinct from inferred sales.

Do not duplicate Aegis grouped Buy results, query engine, scanner, price database, stack posting, or mature Sell behavior unless a concrete incompatibility makes reuse impossible.

## Deferred architecture

Do not implement these until a real requirement justifies them:

- configuration UI;
- SavedVariables migrations;
- shared hook manager more complex than current wrappers;
- dependency graph between modules;
- automated in-client test harness.
