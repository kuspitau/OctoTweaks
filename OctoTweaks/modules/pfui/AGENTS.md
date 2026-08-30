# pfUI module instructions

These instructions apply under `OctoTweaks/modules/pfui/`.

- Current reference version: pfUI 5.5.4 unless `docs/modules/pfui.md` says otherwise.
- Do not edit or redistribute pfUI itself.
- Prefer pfUI extension points where they exist; otherwise use the least invasive external hook that satisfies the requirement.
- Document every pfUI internal symbol or named frame relied upon by a module.
- A version-sensitive hook must have a structural compatibility probe before activation.
- If an update changes the assumptions documented in `docs/modules/pfui.md`, update that file in the same delta.
- In-game tests involving nameplates, casts, combat events, gathering, or other client behavior must remain `PENDING` until actually performed in the OctoWoW client.
