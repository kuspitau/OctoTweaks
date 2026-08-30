# ADR-0002 — Isolate every tweak as a module

Status: Accepted  
Date: 2026-08-30

## Context

OctoTweaks is intended to grow across pfUI, pfQuest, Aegis Exchange, and potentially other addons. A monolithic patch script would create coupling and make failures difficult to diagnose.

## Decision

Each tweak receives a stable module id and independent compatibility/activation path.

A module failure must be recorded locally and must not abort unrelated modules.

## Consequences

- `/ot status` can report module-specific state;
- missing target addons degrade gracefully;
- future agents can work on one subsystem without understanding all others;
- small lifecycle/core abstractions are justified, but target-specific logic stays outside the core.
