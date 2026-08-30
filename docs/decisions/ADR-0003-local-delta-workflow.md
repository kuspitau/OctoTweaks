# ADR-0003 — Local repository with conversation-agent delta handoffs

Status: Accepted  
Date: 2026-08-30

## Context

Independent ChatGPT conversation agents will often work from repository files/context supplied in the conversation rather than modifying the GitHub repository directly. The user wants to review and test successive changes locally before pushing a stable state.

## Decision

The user's local repository is the active development source of truth between pushes.

Normal agent handoff is an overlay-ready `delta_changes.zip`. Required deletions/renames use a temporary `delete_files.bat`; read-only local information gathering may use temporary `get_paths.bat`.

The installed WoW addon is a disposable deployment copy. Root `addon_update.bat` validates the repository, removes the previous deployed addon directory, and copies the current repository `OctoTweaks/` folder into OctoWoW.

`tools/` contains validation/packaging utilities so repository root remains focused on the project entry files plus the frequently used deployment launcher.

## Consequences

Benefits:

- agents do not need direct GitHub write access;
- local state can be tested before publication;
- deltas are small and reviewable;
- removed files cannot linger in the installed addon after clean deployment;
- root remains convenient for the one daily deployment action.

Tradeoffs:

- GitHub may temporarily lag behind local state;
- agents must receive enough current local context to avoid building a delta against stale files;
- deletions require an explicit helper because overlay extraction alone cannot remove files.
