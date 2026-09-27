# AGENTS.md — OctoTweaks repository instructions

## Purpose

OctoTweaks is a modular WoW 1.12 / OctoWoW addon for external compatibility fixes and custom extensions. Conversation agents normally work against the user's local repository and return repository-relative deltas rather than editing GitHub directly.

## Minimal reading path

Before editing:

1. Read `docs/CURRENT_STATE.md`.
2. Read `docs/INDEX.md` and only the documentation routed to the subsystem you will touch.
3. Read any applicable nested `AGENTS.md`.
4. Read `ARCHITECTURE.md` only when changing core behavior, lifecycle, persistence, hooking, deployment, or repository structure.
5. Read a matching note in `docs/work/active/` only when one exists for the task.
6. Inspect only relevant source files unless broader inspection is necessary.
7. Before handoff, read `docs/architecture/delta-delivery-policy.md`.

Do not scan or summarize the whole repository by default.

Historical sources (`CHANGELOG.md` and `docs/work/completed/`) are not part of the default reading path and never override `CURRENT_STATE.md` or the owning current module/architecture documentation.

## Engineering rules

- Never modify installed third-party addon source as an OctoTweaks implementation strategy.
- Prefer: public extension API -> callback/hook -> wrapper -> targeted exposed-function replacement -> invasive workaround only when unavoidable.
- Keep tweaks isolated behind stable module ids; one failed/unavailable module must not prevent unrelated modules from loading.
- Probe external structures before using private internals and treat observations as version-scoped.
- Target conservative WoW 1.12 / Lua 5.0-era behavior unless a newer OctoWoW guarantee is explicitly documented.
- Avoid unrelated refactors during focused feature/fix work.
- Do not silently change module ids, SavedVariables schemas, slash commands, lifecycle semantics, or deployment conventions.
- Module contract and identity details belong in `docs/architecture/module-system.md`.

## Documentation rules

Documentation is part of the change. Follow `docs/architecture/documentation-policy.md` and update only the affected source of truth.

In particular:

- `docs/CURRENT_STATE.md` = compact facts true now;
- `docs/modules/` = reusable module/target behavior and compatibility knowledge;
- `ARCHITECTURE.md` / `docs/architecture/` = durable design/workflow;
- `docs/work/active/` = significant unfinished work only;
- `docs/work/completed/` = retained historical handoff evidence only;
- `docs/ROADMAP.md` = future intentions;
- `CHANGELOG.md` = release/user-visible history.

Keep chronological implementation narration out of current-state/module docs unless the history explains a compatibility invariant future agents need to preserve.

## Validation

Before finishing a repository change, run when possible:

`python tools/check.py`

Do not claim a check or in-game validation passed unless it actually did. If changed runtime behavior is not user-validated, record the exact remaining test as `PENDING`; unrelated stable modules stay stable.

For the user's Windows workflow:

- `tools\check.bat` runs repository checks;
- root `addon_update.bat` validates, replaces the deployed addon, and verifies the TOC;
- `tools\package.bat` builds a clean package and must not bypass repository validation.

## Delta handoff

The exact contract is in `docs/architecture/delta-delivery-policy.md`. Default output is `delta_changes.zip` rooted at repository root and containing only added/modified files. Required deletions/renames use an idempotent repository-relative `delete_files.bat`; do not rely on ZIP extraction to remove files.

The final report must identify the archive, added/modified/deleted/renamed paths, helper scripts supplied, checks actually run, and any user-side runtime validation still required.
