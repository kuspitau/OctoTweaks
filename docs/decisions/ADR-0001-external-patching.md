# ADR-0001 — Prefer external patching over modified third-party addons

Status: Accepted  
Date: 2026-08-30

## Context

OctoTweaks will customize multiple third-party addons. Directly editing those addons makes upgrades, uninstall, provenance, debugging, and repeated agent contribution harder.

## Decision

OctoTweaks will normally leave third-party addon files untouched and apply changes externally.

Preferred order:

1. public extension API;
2. callback/hook;
3. wrapper;
4. targeted exposed-function replacement;
5. invasive workaround only when unavoidable and explicitly documented.

## Consequences

Benefits:

- target addons remain independently upgradable;
- OctoTweaks can be removed cleanly;
- custom behavior is centralized;
- compatibility failures can be isolated by module.

Tradeoff:

- some internals may require fragile version-sensitive hooks, which must be guarded by probes and documentation.
