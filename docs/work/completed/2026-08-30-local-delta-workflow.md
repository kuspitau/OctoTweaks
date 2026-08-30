# Local delta workflow integration

Date: 2026-08-30

## Objective

Align repository instructions and deployment tooling with the user's actual workflow: independent conversation agents return local delta archives; the user tests an evolving local repository before pushing stable state to GitHub.

## Implemented

- root `addon_update.bat`;
- documented overlay-ready `delta_changes.zip` contract;
- temporary `delete_files.bat` and `get_paths.bat` conventions;
- Git ignore rules for temporary handoff files;
- explicit local-source-of-truth architecture decision;
- updated agent, architecture, README, current-state, roadmap, and documentation policies.

## Validation

`python tools/check.py`: **PASS** on 2026-08-30.

`python tools/package.py`: **PASS** on 2026-08-30.

Windows execution of `addon_update.bat` remains pending user-side validation.
