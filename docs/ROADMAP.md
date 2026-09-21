# Roadmap

This file contains future intentions only. It is not authoritative for current implementation or validation status.

## Near term

- Improve Market Workbench automatic-pricing safety before accelerating posting: explicit reference policies, isolated-low-listing safeguards, and vendor-aware floors.
- Design the first configurable pfUI nameplate extension when concrete requirements are ready.

## Candidate future modules / increments

### pfUI

- friendly NPC vs friendly player nameplate behavior;
- nameplate text controls;
- other OctoWoW/SuperWoW compatibility fixes discovered in use.

### pfQuest

- target-specific fixes/extensions as concrete needs are identified.

### Aegis Exchange / Market Workbench

The current Aegis 1.53.29 integration and hosted Workbench baseline are runtime-accepted, including Similar Search across categories that expose no additional AH `invType` slot filter. Candidate later increments are:

- reference policies: Manual, Exact-first, Auto floor, then guarded Smart reference;
- protection against isolated/absurdly low listings and configurable vendor-relative floors;
- `POST + NEXT` only after automatic-reference safeguards are stable;
- expanded sell economics: deposit, AH net, vendor comparison and margin;
- sortable inventory market view built from Aegis market/vendor data;
- tooltip vendor-margin additions using already-known data only;
- explicit freshness display when a stable Aegis accessor/representation has been identified;
- idle/background scanning only after query contention/priority behavior is well characterized;
- deeper analytics (history/distribution/depth/spreads) with observed facts kept distinct from inferred sales.

Do not duplicate Aegis grouped Buy results, query engine, scanner, price database, stack posting, or mature Sell behavior unless a concrete incompatibility makes reuse impossible.

## Deferred architecture

Do not implement these until a real requirement justifies them:

- repository-wide configuration UI;
- repository-wide SavedVariables migration framework;
- shared hook manager more complex than current wrappers;
- dependency graph between modules;
- automated in-client test harness.
