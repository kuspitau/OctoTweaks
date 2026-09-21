# Aegis Exchange integration

## Scope and audited source

OctoTweaks integrates with **Aegis: Exchange** without modifying Aegis files.

Source audit baseline:

- upstream repository: `Torchlite-bit/Aegis_Exchange`;
- backend source-audited versions: current upstream **1.53.29**, previous upstream **1.53.16**, and the user's historical installed **1.20.2** runtime baseline;
- audited current upstream `main` commit for **1.53.29**: `924ce71fee75a61bec08983243385a53ee71ddbc`;
- previous backend audit commit for **1.53.16**: `3b69fac3bf141d8310996f5012406b5ea58f5971`;
- exact upstream commit identified for **1.20.2**: `70f648492607ca1aec6c3df2da42deed21d09c9d`; its `Aegis_Exchange.toc` reports `## Version: 1.20.2`, and its UI structure matches the installed-build behavior already exercised by the user;
- client/API baseline advertised by Aegis: WoW 1.12 / Lua 5.0 on private-server ecosystems including OctoWoW.

Aegis explicitly describes only its Courier transaction integration block as a public contract. The scan, buy, database, sell, tooltip, and UI tables are therefore treated by OctoTweaks as **version-sensitive internals**, even where their source is well structured and upstream tests cover them.

The OctoTweaks integration boundary is split by concern:

- `OctoTweaks/modules/aegis/Adapter.lua` owns scanner, item metadata, Buy/search, market DB, Sell/posting and tooltip-opening internals;
- `OctoTweaks/modules/aegis/UIAdapter.lua` owns the private Aegis presentation seam used by the integrated Workbench.

Higher-level modules must use `OctoTweaks.Aegis`; they must not reach directly into `AegisExchange.*`.

## What the source-audited Aegis builds already provide

The current Aegis implementation already covers substantial parts of the Market Workbench vision. OctoTweaks should orchestrate or extend these capabilities rather than duplicate them.

| Market Workbench concept | Aegis source audit | OctoTweaks implication |
| --- | --- | --- |
| Grouped AH results | **Implemented.** Buy results are grouped by item; a parent expands to individual auctions. | Do not build a second general-purpose Buy browser. The Workbench groups only its Similar Search result set because it needs `SET` reference semantics beside a persistent Target Item. |
| Unit vs stack price | **Implemented.** Buy rows expose per-unit price; individual auctions retain stack count and total buyout. | Reuse Aegis result semantics. |
| Broad/classified search | **Implemented.** Query language and helpers support class, subclass, equipment slot, level bounds, quality/min-quality, buyout-only and stack filters. | Generate the query/filter tuple automatically from the Target Item rather than inventing a new search engine. |
| Exact item selling scan | **Implemented.** Selecting an item on Sell performs a targeted scan and lists competitors. | Keep using Aegis for ordinary exact-item selling. Similar-reference pricing remains the Workbench-specific workflow. |
| Undercut | **Implemented.** Flat copper and percentage undercut are supported; Aegis also exposes price-match behavior. | The Workbench mirrors Match / Flat / % for a manually selected Reference Listing and delegates actual posting to Aegis. |
| Multi-stack posting | **Implemented.** Multiple stacks, leftover handling, deposit display and posting workflow exist. | Reuse Aegis `sell.StartPosting`; OctoTweaks supplies Target/Reference/pricing orchestration. |
| Post/Skip inventory walk | **Implemented.** Aegis 1.20.2 has `StartSellQueue`, `AdvanceSellQueue` and Post/Skip behavior after a bag scan. | Useful design evidence for future `POST + NEXT`, but these UI internals are not consumed in the current slice. |
| Vendor margin | **Implemented in meaningful form.** Vendor list compares merchant value with best known AH value after the consignment cut; Sell warns on bad pricing. | Reuse Aegis vendor and market DB accessors for future economics views. |
| Tooltip economics | **Implemented.** Aegis tooltip extension reads saved market/min-buyout/vendor data without launching a slow scan. | Workbench rows open an ordinary tooltip safely; Aegis' installed tooltip hook enriches it once. |
| Full/targeted scanner | **Implemented.** `scan.Start` walks pages, supports category queries, pause/resume/stop, and respects query pacing. | Reuse it as query transport. |
| Passive market learning | **Implemented.** AH pages observed by the client feed Aegis' price DB. | Useful groundwork for later low-friction data freshness. |
| Background idle scheduler | **Not the requested feature.** | Defer until query priority/contention is deliberately designed. |
| Inventory market analytics | **Partial.** | Future OctoTweaks view can compose Aegis data rather than replace bag handling. |
| Historical/advanced analytics | **Partial foundation.** | Keep observed facts distinct from inferred sales; defer. |
| Target Item vs comparable Reference Listing | **Not exposed as the requested explicit workflow.** | Primary orchestration supplied by `aegis.market_workbench`. |
| Automatic Similar Search | **Search primitives exist; automatic derivation does not.** | Implemented in OctoTweaks from Target metadata. |
| Simultaneous Market + Pricing workbench | **Not native to the audited Aegis workflow.** | The Workbench remains an OctoTweaks view, hosted through the explicitly audited private UI seam on Aegis 1.20.2 and 1.53.29. |

## Audited Aegis symbols and stability assessment

### Namespace and lifecycle

`AegisExchange` is the single global namespace. The audited builds include current `1.53.29`, previous backend baseline `1.53.16`, and historical runtime baseline `1.20.2`; `AegisExchange.loaded` becomes true after Aegis handles its own `ADDON_LOADED`.

**Stability expectation: medium-high structurally, not a formal external API guarantee.** OctoTweaks probes it rather than assuming it.

### Scanner

Useful symbols:

- `AegisExchange.scan.Start(queryOrList, callbacks)`;
- `scan.IsRunning()` / `scan.IsPaused()`;
- `scan.Pause()` / `scan.Continue()` / `scan.Stop()`;
- `scan.GetProgress()`;
- `scan.GetCategories()`.

The audited query shape is `{ name, minLevel, maxLevel, invType, class, subclass, quality }`. Aegis sends vanilla `QueryAuctionItems` calls page by page and waits for `AUCTION_ITEM_LIST_UPDATE`.

**Stability expectation: medium.** These are coherent internals but not a cross-addon public contract.

### Buy/search helpers

Useful symbols:

- `AegisExchange.buy.Search(text, callbacks)`;
- `buy.ClassOptions()`;
- `buy.SubclassOptions(class)`;
- `buy.SlotOptions(class, subclass)`;
- `buy.ClassName`, `SubclassName`, `SlotName`.

`buy.Search` rows include live AH index, name, link, item id, stack count, quality, level, buyout, unit price, seller and time-left data for the current result page.

**Stability expectation: medium-low to medium.** They are implementation helpers; the Workbench probes the subset it needs.

### Item metadata normalizer

`AegisExchange.util.ItemInfo(link)` attempts to normalize different `GetItemInfo` tuple shapes. The supplied 1.20.2 source also documents the 1.12 cold-cache behavior where `GetItemInfo` may initially return `nil`.

Runtime testing exposed an additional incompatibility on the user's Octo client: fields for `Venomshroud Boots` were shifted (`type=INVTYPE_FEET`, subtype holding the texture path, bad required level). OctoTweaks therefore validates Aegis' named result and, when structurally shifted, re-normalizes the raw tuple by texture/equipment-location anchors. It also warms a hidden bag tooltip and retries boundedly for cold-cache Target selection.

**Stability expectation: medium-low.** `util.ItemInfo` remains a first path, but the adapter owns validation/fallback/diagnostics.

### Market database

Useful accessors:

- `AegisExchange.db.MarketValue(itemId)`;
- `AegisExchange.db.MinBuyout(itemId)`;
- `AegisExchange.db.GetVendor(itemId)` when present;
- `AegisExchange.db.SeenCount(itemId)` when present.

**Stability expectation: medium.** Central readers, still behind the adapter.

### Sell engine

Useful audited symbols include `sell.Suggest`, `sell.ScanItem`, `sell.Post`, `sell.StartPosting`, `sell.PostingActive`, `sell.CancelPosting`, `sell.CountInBags`, `sell.MaxStacks`, and existing undercut/settings machinery.

**Stability expectation: medium for read-only suggestion/status, lower for posting orchestration.** OctoTweaks delegates stack assembly and actual posting to Aegis rather than duplicating those mechanics.

### Tooltip

`AegisExchange.tooltip.Extend(gtt, itemId, count)` exists, but direct calls are avoided because Aegis already hooks tooltips.

The OctoWoW runtime test exposed a vanilla edge case where a full coloured chat hyperlink can raise `Unknown link type` in native `GameTooltip:SetHyperlink`. The adapter prefers a verified current `SetAuctionItem` row, otherwise strips to the bare `item:...` payload under `pcall`, and finally falls back to the item name.

**Stability expectation for direct `tooltip.Extend`: low/avoid.** Only tooltip opening is normalized by OctoTweaks.

### Aegis UI extension seam — 1.20.2 and 1.53.29

The exact **1.20.2** source at commit `70f648492607ca1aec6c3df2da42deed21d09c9d` remains the historical runtime baseline. The exact current **1.53.29** source at upstream main commit `924ce71fee75a61bec08983243385a53ee71ddbc` was re-audited on 2026-09-19 for the same private extension seam.

Relevant structure:

- `AegisExchange.ui.BuildWindow()` creates one top-level `AegisExchangeFrame` and one shared content frame;
- its private static tab list initially builds `Buy`, `Sell`, `Auctions`, `Crafting`, `History`, and `Scan` (displayed as `Aegis`);
- after construction, the actual runtime dispatch tables are public fields `ui.subtabs` and `ui.panels`;
- `ui.SelectSubTab(name)` iterates those tables dynamically, showing/tinting the matching key and hiding the other panels;
- `ui.RefreshCurrentTab()` has explicit branches only for Aegis' own keys and simply does nothing extra for an unknown extension key;
- `ui.OpenWindow()` builds/shows Aegis then routes through `ui.SelectSubTab`;
- the host is resizable (`MIN_H=492`, `MAX_H=900` in the audited current 1.53.29 source as well), and size persistence is committed by Aegis' resize-grip path rather than by arbitrary `SetHeight` calls.

This gives OctoTweaks a narrow extension seam without replacing Aegis Buy/Sell: append one button/panel to the dynamic tables, then let Aegis' own dispatcher hide/show it.

`UIAdapter.lua` probes all structures used and admits only the explicit source-audited allowlist (`1.20.2`, `1.53.29`). It wraps `OpenWindow` and `SelectSubTab` save-and-delegate style and isolates callback failures. The Workbench module itself never accesses `AegisExchange.ui`. Unknown versions fail closed rather than assuming the private presentation contract remained stable.

The existing Workbench is 870x500 frame units. At Aegis' minimum height, the content well is too short, so the adapter temporarily raises the host to 620 while the Workbench tab is active. It restores the prior height **before** Aegis refreshes a normal tab. If the user manually resizes while Workbench is active, that new height is kept instead of being overwritten. `AUCTION_HOUSE_CLOSED` also releases the temporary height.

**Stability expectation: low/private.** This is why activation is exact-version-gated to the audited allowlist. An unknown/newer Aegis version keeps `aegis.market_workbench` isolated from the private presentation hook instead of guessing at presentation internals.

## OctoTweaks adapter surface

`aegis.integration` exposes `OctoTweaks.Aegis` backend capabilities for:

- namespace/load state;
- scan start/control;
- category options;
- normalized item info;
- Buy search;
- market DB readers;
- Sell suggestion/posting;
- tooltip opening/extension presence.

The private UI layer adds explicit methods such as:

- `ProbeWorkbenchUIHost()`;
- `InstallUIExtension(spec)`;
- `EnsureUIExtensionAttached()`;
- `SelectUIExtension(key)`;
- `SelectAegisSubTab(name)`;
- `AcquireWorkbenchHostHeight()` / `ReleaseWorkbenchHostHeight()`;
- `GetUIExtensionDiagnostics()`.

Minimum backend Workbench activation is independent of the UI extension. Therefore a UI probe failure cannot disable phase-1 search/pricing/posting.

Diagnostics:

```text
/otaegis
/otaegis status
/otaegis probe
/otaegis caps
/otmarket status
```

The backend diagnostics report the detected Aegis version/capabilities. `/otmarket status` now appends the Aegis UI extension audit/attachment state when `aegis.market_workbench_ui` is enabled.

## `aegis.market_workbench` workflow

Phase-1 status: **IMPLEMENTED; general workflow runtime-accepted on current Aegis 1.53.29, with the targeted Similar Search empty-slot-option correction still awaiting its short cross-category regression matrix**. Historical 1.20.2 remains a fully exercised baseline.

Entry point:

```text
/otmarket
```

Behavior:

1. Drop an actual bag item onto `Target Item`, or use `/otmarket target <bag> <slot>`. Cold item metadata is warmed/retried boundedly.
2. Target Item is retained independently from every Reference Listing choice.
3. `SIMILAR SEARCH` derives AH class, subclass, equipment slot and `requiredLevel +/- N`.
4. `Buyout only` and `Exact quality` are optional direct controls.
5. Aegis owns query pacing/page traversal; OctoTweaks reads completed pages and preserves exact listing semantics.
6. Results are grouped by item id + displayed name, with expandable individual listings.
7. Hover uses the adapter's safe tooltip path.
8. `SET` changes only Reference Listing.
9. Pricing supports `match`, `flat`, and `percent`; default flat undercut is 1 copper.
10. `POST` delegates stack assembly/submission to Aegis `sell.StartPosting` with stack size, number of auctions and 6h/24h/72h duration.

## `aegis.market_workbench_ui` integration

Implementation status: **IMPLEMENTED; RUNTIME PASS on current Aegis 1.53.29 by user acceptance (2026-09-21)**. Historical 1.20.2 remains a runtime baseline; unknown private-UI versions still fail closed.

On exact source-audited Aegis 1.20.2 or 1.53.29:

- a seventh `Workbench` sub-tab is appended after Aegis' `Aegis` tab;
- the validated Workbench frame is reparented into a dedicated Aegis content panel;
- its inner standalone close button and drag behavior are disabled while embedded;
- `/otmarket` selects the integrated tab while the Aegis window is open;
- `/otmarket close` and toggle behavior return to Aegis `Buy` rather than leaving an empty selected panel;
- outside the Aegis window, `/otmarket` restores the original standalone parent/drag/close behavior;
- while the integrated Workbench is active, plain right-click on an inventory item sets the Target Item through the same validated `SetTargetFromBag` path; Shift/Ctrl/Alt-right-click and all right-clicks outside Workbench fall through unchanged;
- plain-right-click is now a one-shot quick workflow: once Target metadata resolves, OctoTweaks starts Similar Search automatically; when Aegis polling completes, the first priced result in Workbench sort order is selected as Reference Listing automatically; drag/drop, slash Target selection, and later manual `SET` remain available;
- the auto-reference path does not rewrite pricing settings: Match/Flat/Percent mode and amount continue to come from the persisted Market Workbench settings, so a user's `% 5` preset is reused immediately;
- the integrated pricing column adds a gross `Gain vs vendor` figure equal to `Suggested Price - target vendor value` per item. Iteration 5 audits the supplied Improved SellValue addon: it exposes an initialized/merchant-updated global `SellValues` table keyed by strings such as `item:15611`; Workbench now reads that table read-only as the preferred optional vendor source, then falls back to `AegisExchange.db.GetVendor`/Aegis market data. The same resolved vendor value is reflected in the Target-market summary. The gain label uses its own larger-font row below Suggested Price instead of crowding the Stack controls. Negative/zero is grey; defaults are green `<10s`, yellow `<40s`, orange `<70s`, red `<1g`, purple `>=1g`. The four positive cutoffs persist under `marketWorkbench.gainThresholds` and can be changed with `/otmarket gains <green> <yellow> <orange> <red>` (values in silver) or reset with `/otmarket gains reset`;
- the embedded Target drop button is explicitly brought above the host and keeps its original `OnReceiveDrag` path, with an `OnMouseUp` cursor-item fallback for the real-client case where the reparented host did not deliver the drop event;
- the complete Workbench child-frame tree is rebased after reparenting. Runtime iteration 2 proved why this is necessary on the tested client: parent FontStrings and the separately raised Target box rendered, while existing child `Button`, `EditBox`, `CheckButton`, result-row and posting controls retained stale absolute frame levels below Aegis and disappeared/could not receive clicks;
- leaving the Workbench view triggers the existing Workbench `OnHide` ownership cleanup, so Workbench-owned scanning/posting is stopped without cancelling unrelated Aegis work.

No Aegis file is modified. Aegis Buy/Sell/listing widgets are not copied or replaced.

## Runtime validation evidence — Aegis 1.20.2


Phase 1 is **PASS in OctoWoW** for the installed Aegis 1.20.2 build. Confirmed by the user:

- Target Item selection and retention with corrected metadata;
- Similar Search while the custom Aegis AH UI remains active;
- page polling/result collection;
- grouped result interaction;
- hover tooltips after the vanilla full-link fix;
- independent Reference Listing selection through `SET`;
- Suggested Price calculation/display;
- direct Aegis-backed `POST`.

That PASS remains the baseline and is not downgraded by this UI-only slice.

The integrated sub-tab has **runtime PASS for the current Market Workbench v1 pricing workflow** on Aegis 1.20.2. The user confirmed: (1) the integration module enables, (2) exactly one Workbench tab is present, (3) the embedded two-column layout and controls work, (4) plain right-click selects the Target with correct metadata, (5) the quick chain starts Similar Search automatically, selects the first priced result as Reference, preserves the user's Percent-5 preset, and produces Suggested Price, and (6) the iteration-5 SellValue-backed vendor lookup plus the repositioned/color-banded `Gain vs vendor` display work correctly in game. The previously observed Bonelink Cape case (`71s25c` Suggested Price vs SellValue `43s69c` vendor) is therefore resolved. Direct Aegis-backed `POST` was already runtime-confirmed in the phase-1 backend workflow; `POST + NEXT` remains future work.

### Aegis 1.53.29 runtime baseline — PASS

Current Aegis 1.53.29 at commit `924ce71fee75a61bec08983243385a53ee71ddbc` is both source-audited and runtime-accepted with the current hosted Workbench. The user confirmed on 2026-09-21 that the new Workbench works well with the latest Aegis. This promotes the integration/UI compatibility baseline to runtime PASS.

The narrower Workbench Similar Search defect affecting already-specific equipment subclasses (observed `INVTYPE_2HWEAPON`, `INVTYPE_RANGEDRIGHT`, and `INVTYPE_SHIELD`) is now closed by user acceptance. OctoTweaks leaves `invType=nil` when Aegis exposes no `SlotOptions(class, subclass)`, while retaining strict localized slot matching whenever Aegis does expose slot options. The user confirmed the corrected Workbench no longer shows the reported failures and works normally across the affected item families.

This behavior is part of the current `aegis.market_workbench` stable runtime baseline.

## Current limitations

- Similar Search requires exact class/subclass resolution. It now requires a slot only when Aegis exposes one or more AH slot options for that category; empty slot-option lists correctly fall back to class+subclass. `/otmarket itemprobe <bag> <slot>` remains the diagnostic escape hatch for a new client tuple shape.
- Search refuses to steal the query channel while Aegis scan/Buy/posting activity owns it.
- Workbench uses Aegis' scanner for the comparable set rather than binding to Aegis Buy row widgets. This is deliberate: Target/Reference state and complete comparable collection differ from ordinary Buy browsing.
- Group identity remains item id + displayed name; random-property identity needs runtime evidence before stronger semantics are chosen.
- Bid-only listings cannot become pricing references because they have no buyout/unit price.
- The integrated UI seam is exact-version-gated to the source-audited allowlist: Aegis 1.20.2 and 1.53.29. The older 1.53.16 backend audit does not by itself authorize that private presentation hook. Unknown versions remain disabled until separately audited.
- The sub-tab is created after Aegis' one-shot skin pass; the current embedded layout is runtime-accepted, while purely visual pfUI parity remains a cosmetic consideration rather than validation debt.
- AH-cut/deposit-aware net margin, `POST + NEXT`, advanced/smart automatic reference policies, inventory valuation, background scanning, freshness UI and analytics remain deferred. The iteration-5 gain line is intentionally only the gross Suggested-vs-vendor difference; SellValue is an optional read-only vendor source, not a new hard dependency.

## Runtime regression procedure

### General Workbench baseline — PASS; re-check only behavior touched by future changes

1. Enable Aegis: Exchange and OctoTweaks; open the Auction House.
2. Run `/ot status`; expect `aegis.integration = ENABLED`, `aegis.market_workbench = ENABLED`, and on exact audited 1.20.2 or 1.53.29 `aegis.market_workbench_ui = ENABLED`.
3. Run `/otaegis probe` and `/otmarket status`; confirm the detected Aegis version plus its matching UI audit commit/state (`70f64849...` for 1.20.2 or `924ce71f...` for 1.53.29).
4. Select a bag equipment Target and confirm name/type/subtype/slot/required level remain correct.
5. Run Similar Search with default `+/- 2`; confirm it stays in Aegis UI and returns the expected comparable category/range.
6. Expand parent/child rows, hover both, and verify listing values/tooltips remain correct.
7. `SET` a different comparable item and confirm Target remains unchanged.
8. Check `flat 1`, `match`, and a simple percent mode.
9. With a disposable low-risk item, post one auction and confirm the actual owned auction matches Suggested Price.

### Integrated-UI v1 baseline — runtime PASS

10. **PASS** — Aegis shows exactly one seventh **Workbench** sub-tab after **Aegis**, with the integration module enabled.
11. **PASS** — the two-column Workbench is visible inside Aegis with the expected integrated layout.
12. **PASS** — plain-right-click on a bag item selects the Target Item with correct metadata and without requiring drag-and-drop. Modified-right-click fall-through remains to be checked separately.
13. **PASS** — iteration 3 restored the embedded frame controls; the user confirmed the corrected control layer works.
14. **PASS:** iteration-4 plain-right-click quick workflow starts Similar Search automatically, selects the first priced result as Reference, preserves the current pricing preset, and fills Suggested Price. Runtime example: Bonelink Cape → Royal Cape of the Owl at `75s` → Percent 5 → `71s25c`.
15. **PASS** — iteration 5 corrected the SellValue-backed vendor/gain display in game. The Workbench now reads SellValue when Aegis lacks a vendor value, and the gain row is readable in its dedicated position.
16. Exercise one negative vendor comparison (grey) and at least one other positive band. Run `/otmarket gains` to print current cutoffs; optionally set a harmless test set such as `/otmarket gains 10 40 70 100`, then `/otmarket gains reset`.
17. Retest drag-and-drop as the secondary Target-input path and confirm it does **not** force the quick auto-search/auto-SET path unless explicitly changed later.
18. Switch `Workbench → Buy → Sell → Workbench`. Confirm normal Aegis tabs repaint correctly, the Workbench state (Target/Reference/options) is retained, and no stale overlay remains.
19. Resize the Aegis window taller while Workbench is selected, switch to Buy, and confirm OctoTweaks does **not** undo the user's manual resize. Repeat without manual resizing and confirm the temporary height is restored.
20. Run `/otmarket` while the Aegis window is open; it should select the integrated Workbench tab. `/otmarket close` (or toggling `/otmarket`) should return to Buy rather than leave a blank Workbench panel.
21. Close the Auction House from Workbench, reopen it, and confirm the Workbench tab reattaches only once and remains usable.
22. Start a Workbench Similar Search, switch to Buy before completion, and confirm only the Workbench-owned scan is stopped cleanly. Repeat with a low-risk posting job only if the cancellation behavior can be safely observed.
23. With pfUI enabled, inspect the new tab and embedded frame for clipping/overlap. Functional correctness takes priority; report any purely visual mismatch separately.
24. Run `/ot status`, `/otaegis probe`, and `/otmarket status` after the test and return any Lua errors plus those outputs.

The Aegis 1.53.29 integration, hosted Workbench, and Similar Search slot-option fallback are **runtime PASS by user acceptance**. There is no current Workbench validation debt. The next functional milestone is safer auto-pricing safeguards before `POST + NEXT`.
