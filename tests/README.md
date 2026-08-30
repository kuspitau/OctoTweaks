# Validation

## Automated/static

Run from repository root:

```text
python tools/check.py
```

The checker uses only the Python standard library.

On Windows you may also use:

`tools\check.bat`

## Local deployment test

1. Ensure the local repository contains the desired delta-applied state.
2. Run root `addon_update.bat`.
3. Confirm repository checks pass before deployment.
4. Confirm the old deployed `Interface\AddOns\OctoTweaks` is replaced.
5. Confirm the deployed directory contains `OctoTweaks.toc` and matches current repository addon files.
6. Start/reload OctoWoW and continue with the runtime smoke test.

## In-game smoke test — bootstrap

1. Enable OctoTweaks and pfUI.
2. Log in.
3. Run `/ot status`.
4. Confirm the addon loads without a Lua error.
5. Confirm `pfui.libpredict_fix` is reported as `ENABLED` when the expected pfUI structure is present.

## In-game regression test — libpredict fix

1. Reproduce the gathering/mining action that previously triggered the pfUI `endtime` nil error.
2. Confirm the error no longer occurs.
3. Cast an ordinary spell with a cast time and confirm normal pfUI behavior remains intact.
4. Test an interrupted cast if practical.
5. Repeat with `/ot debug on` if diagnosis is needed.
