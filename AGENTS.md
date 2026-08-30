# AGENTS.md — OctoTweaks repository instructions

## Purpose

OctoTweaks is a modular WoW 1.12 / OctoWoW addon that applies external compatibility fixes, bug fixes, and custom extensions to third-party addons without maintaining modified copies of those addons.

The repository is designed for repeated contribution by independent coding agents working in conversation windows. Agents normally do **not** edit the user's GitHub repository directly. Their normal deliverable is a repository-relative delta archive that the user applies to the local repository and later commits/pushes once stable.

## Start here

Before editing:

1. Read `docs/CURRENT_STATE.md`.
2. Read `docs/INDEX.md` and only the documentation for the subsystem you will touch.
3. Read `ARCHITECTURE.md` when changing core behavior, module lifecycle, persistence, hooking policy, deployment workflow, or repository structure.
4. Obey any nested `AGENTS.md` that applies to the files you edit.
5. Inspect only the source files relevant to the requested task unless broader inspection is necessary.
6. If a task has an active work note in `docs/work/active/`, read it before changing code.
7. Read `docs/architecture/delta-delivery-policy.md` before preparing a handoff archive.

Do not scan or summarize the entire repository by default.

## Local-repository / conversation-agent workflow

Assume this workflow unless the user explicitly says otherwise:

1. the user has a local OctoTweaks repository;
2. the agent receives enough repository files/context in the conversation to make a focused change;
3. the agent produces `delta_changes.zip` containing only added/modified repository files at their repository-relative paths;
4. if repository files must be deleted or renamed, the handoff also includes a safe `delete_files.bat`;
5. if more local path/file information is required, the agent may provide a non-mutating `get_paths.bat` for the user to run;
6. the user extracts the delta over the local repository and runs any deletion helper;
7. the user runs validation and `addon_update.bat` from repository root;
8. the user tests in OctoWoW;
9. only after the local state is stable does the user commit/push to GitHub.

Do not assume that a GitHub branch, PR, or direct repository write is available.

## Delta handoff rules

See `docs/architecture/delta-delivery-policy.md` for the full contract.

In summary:

- `delta_changes.zip` must be rooted as if extracted directly over repository root.
- Include only added/modified files unless the user explicitly requests a full repository/bootstrap.
- Never rely on ZIP extraction to delete obsolete files.
- Use `delete_files.bat` for required deletions/renames.
- `delete_files.bat` must be idempotent, repository-relative, explicit, and narrowly scoped; avoid broad wildcards.
- `get_paths.bat` must be read-only and only gather information needed for the next step.
- Temporary handoff helpers are ignored by Git and should not become project source files.
- Do not include `dist/` artifacts unless the user requests a distributable package.
- Always list added, modified, renamed, and deleted paths in the final handoff report.

## Core engineering rules

- Do not modify third-party addon source files as part of OctoTweaks.
- Do not copy third-party addon source into this repository unless a narrowly scoped fixture is legally and technically justified and documented.
- Prefer, in order: public extension API -> callback/hook -> wrapper -> targeted exposed-function replacement -> invasive workaround only when unavoidable.
- Keep each tweak isolated as a module with a stable module id.
- A failed or unavailable module must not prevent unrelated modules from loading.
- Use compatibility probes before touching third-party internals.
- Treat observations about one addon version as version-scoped knowledge, not universal truth.
- Target WoW 1.12-era Lua. Avoid syntax or standard-library assumptions introduced after Lua 5.0 unless OctoWoW explicitly guarantees them and that dependency is documented.
- Avoid unrelated refactors during a feature/fix task.
- Do not silently change public module ids, SavedVariables layout, slash commands, lifecycle semantics, or deployment conventions.

## Module identity

Use ids of the form:

`<target>.<feature_or_fix>`

Examples:

- `pfui.libpredict_fix`
- `pfui.friendly_nameplates`
- `pfquest.some_feature`

Each module should document at least:

- id
- category (`compatibility`, `fix`, or `feature`)
- target addon/system
- default enabled state
- tested target version(s), when version-sensitive
- purpose
- compatibility assumptions

## Documentation is part of the change

A code change is not complete when it makes authoritative documentation stale.

Read `docs/architecture/documentation-policy.md` and update only the sources of truth affected by the change.

Typical routing:

| Change | Update |
|---|---|
| Real current implementation/status changed | `docs/CURRENT_STATE.md` |
| Target-addon knowledge or module behavior changed | `docs/modules/<target>.md` |
| Core architecture/workflow changed | `ARCHITECTURE.md` and relevant architecture doc |
| Durable architectural decision made | add/update an ADR in `docs/decisions/` |
| Significant work remains incomplete | create/update `docs/work/active/<task>.md` |
| Significant active work completed | move/finalize note under `docs/work/completed/` |
| Future intention only | `docs/ROADMAP.md` |
| User-visible release history | `CHANGELOG.md` |

Do not turn `AGENTS.md`, `CURRENT_STATE.md`, or source comments into chronological journals.

## Completion states

Do not use "done" ambiguously. Distinguish:

- implementation complete
- static/desktop validation complete
- in-game/runtime validation complete

If runtime validation cannot be performed by the agent, leave it explicitly `PENDING` and provide the exact manual test required.

## Validation and local deployment

Before finishing a code change, run when the execution environment permits:

`python tools/check.py`

For the user's Windows workflow:

- `tools\check.bat` runs repository checks;
- root `addon_update.bat` validates first, deletes the previously deployed `Interface\AddOns\OctoTweaks`, and copies the current repository `OctoTweaks\` folder into the game;
- `tools\package.bat` builds a clean distribution ZIP when needed.

Do not claim a validation passed unless it was actually executed. Agents working only in conversation generally cannot claim the final OctoWoW in-game validation.

## Work handoff

For a significant unfinished task, update an active work note with:

- objective
- current status
- completed work
- remaining work
- relevant files
- discoveries/assumptions
- rejected approaches when important
- validation already run
- validation still required

The next agent should be able to resume from that note plus the targeted documentation and code.

## Final report

When completing a repository task, report:

1. files added/modified;
2. files deleted/renamed and whether `delete_files.bat` is required;
3. behavior added/changed;
4. validation commands actually run and results;
5. runtime checks still pending;
6. documentation/status updates made;
7. remaining known limitations or follow-up work;
8. the exact handoff archive (`delta_changes.zip` by default) and any temporary helper scripts supplied.
