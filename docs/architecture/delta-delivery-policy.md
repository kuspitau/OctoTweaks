# Conversation-Agent Delta Delivery Policy

## Purpose

The normal OctoTweaks development loop uses independent conversation agents that cannot be assumed to write directly to the user's GitHub repository.

The user's **local repository** is the active development source of truth. GitHub may lag behind while a delta is being tested.

## Default deliverable

Unless the user requests a full repository/bootstrap, deliver:

`delta_changes.zip`

The archive contains only files that are new or modified by the task.

Every archived path must be relative to repository root so the user can extract the archive directly over the local repository.

Example:

```text
delta_changes.zip
├── OctoTweaks/
│   ├── OctoTweaks.toc
│   └── modules/pfui/FriendlyNameplates.lua
├── docs/
│   ├── CURRENT_STATE.md
│   └── modules/pfui.md
└── CHANGELOG.md
```

Do **not** add an extra wrapper directory such as `delta_changes/` unless explicitly requested, because that would prevent direct overlay extraction.

## Added and modified files

Place their complete new contents in `delta_changes.zip` at their normal repository-relative path.

Do not ship textual diff/patch files as the primary deliverable unless requested; the default is overlay-ready files.

## Deleted files

ZIP extraction cannot reliably remove files that no longer belong in the repository.

When deletion is required, include a temporary root helper:

`delete_files.bat`

Requirements:

- paths are resolved relative to the batch file/repository root;
- operations are explicit and narrowly scoped;
- the script is safe to run more than once (missing targets are not fatal);
- no broad destructive wildcard such as deleting an entire source tree unless the task explicitly requires it;
- each intended deletion is echoed;
- failures produce a non-zero exit code where practical;
- it must not delete user data, SavedVariables, the Git repository, or unrelated addon files.

For a rename, the delta normally contains the new path and `delete_files.bat` removes the old path.

`delete_files.bat` is a handoff helper, not maintained project source, and is ignored by Git.

## `get_paths.bat`

If the agent cannot proceed safely without information about the user's local repository/file layout, it may supply:

`get_paths.bat`

This helper must be **read-only**. It may enumerate requested files/directories, metadata, or selected text/path information into a `.txt` result for the user to return to the conversation.

It must not modify, move, rename, or delete repository/game files.

`get_paths.bat` is temporary and ignored by Git.

## Documentation in deltas

Documentation updates are normal delta contents, not a separate afterthought.

The delta must leave authoritative docs correct for the state that will exist immediately after extraction/deletion-helper application.

Do not mark user-side deployment or in-game validation as passed merely because the delta was generated successfully.

## Generated artifacts

Do not include by default:

- `dist/`
- installable release ZIPs
- Python caches
- temporary logs
- local test outputs

Include a package only if the user specifically requests one.

## Agent validation before handoff

When the agent has an executable repository snapshot, run:

`python tools/check.py`

If the agent cannot execute the resulting repository, state that explicitly rather than claiming PASS.

The user-side normal sequence after applying the delta is:

```text
extract delta_changes.zip over local repo
→ run delete_files.bat if supplied
→ run tools\check.bat (optional if addon_update will run checks itself)
→ run root addon_update.bat
→ /reload or restart WoW
→ perform requested in-game tests
→ update/follow up on runtime status as needed
→ commit/push stable local repository
```

## Final handoff report

Always report:

- archive supplied;
- added paths;
- modified paths;
- deleted paths;
- renamed paths;
- whether `delete_files.bat` is supplied;
- whether `get_paths.bat` is supplied;
- static checks actually executed and results;
- user-side checks still required.
