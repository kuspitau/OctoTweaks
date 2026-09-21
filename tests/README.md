# Validation

## Automated/static

Run from repository root:

```text
python tools/check.py
```

The checker uses only the Python standard library. On Windows, `tools\check.bat` is equivalent.

## Local deployment smoke test

1. Apply the desired delta to the local repository.
2. Run `addon_update.bat`.
3. Confirm repository checks pass before deployment and OctoTweaks loads without a Lua error.
4. Run `/ot status` and confirm expected modules are `ENABLED` (or intentionally `WAITING` for character-specific modules).

Detailed reusable regression procedures live in the target module docs rather than being duplicated here.

## Current targeted runtime regression

None. The current stable baseline has been accepted in game.

Future changes should reopen validation only for behavior plausibly affected by that change; reusable procedures remain in the relevant module docs.
