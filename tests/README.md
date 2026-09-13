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

## In-game integration test — Aegis Market Workbench prototype

The authoritative detailed sequence is in `docs/modules/aegis.md`.

Minimum smoke test:

1. Enable Aegis: Exchange and OctoTweaks, then open the Auction House.
2. Run `/ot status` and confirm `aegis.integration` plus `aegis.market_workbench` are `ENABLED`.
3. Run `/otaegis probe`; on the current setup expect Aegis 1.20.2 to be reported as source-audited but still runtime-incomplete.
4. Run `/otmarket` and select a real bag item as Target. The previous cold-cache failure should resolve automatically. If it does not, run `/otmarket itemprobe <bag> <slot>` and capture the output. Then run Similar Search.
5. Verify grouped results, child listings, and that hover tooltips open with no `Unknown link type` error; `SET` must change Reference without changing Target.
6. Verify Match, Flat 1c, and Percent suggested-price arithmetic.
7. With a disposable/low-risk item, post exactly one auction through the Workbench and verify item/stack/duration/unit price against the resulting owned auction; then test Workbench posting cancellation separately.
8. Confirm Similar Search refuses to steal the query channel while an Aegis scan is running or paused.
9. Stop/close a Workbench-owned scan/posting job and confirm only that owned operation terminates cleanly.

Current status: **PASS for the phase-1 workflow on Aegis 1.20.2** — Target capture, Similar Search/polling, result interaction, tooltip hover, `SET`, Suggested Price, and direct `POST` have been confirmed in OctoWoW. Treat the sequence above as a regression test after future Aegis integration changes.

### Aegis Market Workbench runtime compatibility

For Aegis 1.20.2 on OctoWoW, keep the **Aegis custom AH UI** active while testing Similar Search. Target metadata must show the actual class/subclass/slot/required level; `INVTYPE_*` must not appear as item class and an `Interface\\Icons\\...` path must not appear as subtype. Similar Search must start without switching to Blizzard AH. If metadata is wrong, capture `/otmarket itemprobe <bag> <slot>`; the probe prints raw `GetItemInfo` returns through 12 plus adapter-normalized fields.
