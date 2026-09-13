# Aegis Exchange integration

## Scope and audited source

OctoTweaks integrates with **Aegis: Exchange** without modifying Aegis files.

First integration audit:

- upstream repository: `Torchlite-bit/Aegis_Exchange`;
- source-audited addon versions: **1.53.16** upstream and the user's installed **1.20.2** ZIP;
- audited upstream `main` commit for 1.53.16: `3b69fac3bf141d8310996f5012406b5ea58f5971`;
- 1.20.2 audit source: the exact installed `Aegis_Exchange` folder supplied after the first OctoWoW runtime probe.
- client/API baseline advertised by Aegis: WoW 1.12 / Lua 5.0 on 1.18.1 private-server ecosystems including OctoWoW.

Aegis explicitly describes only its Courier transaction integration block as a public contract. The scan, buy, database, sell, tooltip, and UI tables are therefore treated by OctoTweaks as **version-sensitive internals**, even where their source is well structured and upstream tests cover them.

All OctoTweaks access to those internals belongs in `OctoTweaks/modules/aegis/Adapter.lua`. Higher-level modules must not reach into `AegisExchange.*` directly.

## What the source-audited Aegis builds already provide

The current Aegis implementation already covers substantial parts of the Market Workbench vision. OctoTweaks should orchestrate or extend these capabilities rather than duplicate them.

| Market Workbench concept | Aegis source audit | OctoTweaks implication |
| --- | --- | --- |
| Grouped AH results | **Implemented.** Buy results are grouped by item; a parent expands to individual auctions. | Do not build a second general-purpose Buy browser. The prototype only groups its own Similar Search result set because it needs `SET` reference semantics beside a persistent Target Item. |
| Unit vs stack price | **Implemented.** Buy rows expose per-unit price; individual auctions retain stack count and total buyout. | Reuse Aegis result semantics. |
| Broad/classified search | **Implemented.** Query language and helpers support class, subclass, equipment slot, level bounds, quality/min-quality, buyout-only and stack filters. | Generate the query/filter tuple automatically from the Target Item rather than inventing a new search engine. Target metadata is read through Aegis' cross-client `util.ItemInfo` normalizer rather than positional `GetItemInfo` returns. |
| Exact item selling scan | **Implemented.** Selecting an item on Sell performs a targeted scan and lists competitors. | Keep using Aegis for ordinary exact-item selling. Similar-reference pricing is the new workflow. |
| Undercut | **Implemented.** Flat copper and percentage undercut are supported; Aegis also exposes price-match behavior in Sell. Default data uses flat 1c. | The Workbench mirrors Match / Flat / % locally for a manually selected Reference Listing and now delegates actual posting to Aegis. |
| Multi-stack posting | **Implemented.** Multiple stacks, leftover handling, deposit display and posting workflow exist. | Reuse Aegis `sell.StartPosting`; OctoTweaks supplies only Target/Reference/pricing orchestration and post controls. |
| Post/Skip inventory walk | **Implemented.** After a bag scan, Aegis can walk sellable bag items with Post / Skip. | Strong basis for a future `POST + NEXT` workflow. |
| Vendor margin | **Implemented in meaningful form.** Vendor list compares merchant value with best known AH value after the consignment cut; Sell also warns on bad pricing. | Reuse Aegis vendor and market DB accessors for future economics views. |
| Tooltip economics | **Implemented.** Aegis tooltip extension reads saved market/min-buyout/vendor and related data; it does not need to launch a slow AH query for the hover. | Workbench rows use ordinary `GameTooltip`; Aegis' installed tooltip hook enriches it automatically. Do not call `tooltip.Extend` directly and risk duplicate lines. |
| Full/targeted scanner | **Implemented.** `scan.Start` walks pages, supports category queries, pause/resume/stop, and respects `CanSendAuctionQuery()`. | Reuse it as the query transport. |
| Passive market learning | **Implemented.** Every AH result page observed by the client feeds Aegis' price DB, including manual/buy browsing. | Useful groundwork for future low-friction data freshness. |
| Background idle scheduler | **Not the same feature.** Aegis can scan and pause, but the audited code does not provide the requested priority scheduler `user > target > bags > background`. | Defer until runtime behavior and query contention are understood. |
| Inventory market analytics | **Partial.** Sell has `Your Bags`, vendor workflow and inventory-related data, but not the full proposed sortable valuation/margin/freshness workbench view. | Future OctoTweaks view can compose Aegis DB data rather than replace bag handling. |
| Historical/advanced analytics | **Partial foundation.** Aegis maintains market history/value data and transaction/history features, but the proposed depth/distribution/spread workbench is broader. | Keep observed facts distinct from inferred sales; defer analytics. |
| Target Item vs comparable Reference Listing | **Not exposed as the requested explicit workflow.** Sell keeps an actual sell item and lets a competitor influence price, but the audited workflow is centered on competition for that item rather than a separately selected comparable item. | This is the primary new orchestration supplied by `aegis.market_workbench`. |
| Automatic Similar Search from a bag item | **Search primitives exist; automatic derivation does not.** | Implement in OctoTweaks by mapping `GetItemInfo()` class/subclass/equip slot/required level to Aegis category indices. |
| Simultaneous Market + Pricing workbench | **Not the audited Aegis presentation.** Buy and Sell capabilities exist but as their own Aegis views/workflows. | Prototype a focused side-by-side orchestration UI without replacing Aegis' main window. |

## Audited Aegis symbols and stability assessment

### Namespace and lifecycle

`AegisExchange` is the single global namespace. The audited builds report `1.53.16` and `1.20.2` respectively, and `AegisExchange.loaded` becomes true after Aegis handles its own `ADDON_LOADED`. The scanner/category/sell/database symbols used by this prototype are present in the supplied 1.20.2 build with the expected signatures.

**Stability expectation: medium-high structurally, but not a formal external API guarantee.** The namespace is fundamental to Aegis itself. OctoTweaks still probes it rather than assuming it.

### Scanner

Useful symbols:

- `AegisExchange.scan.Start(queryOrList, callbacks)`;
- `scan.IsRunning()`;
- `scan.IsPaused()`;
- `scan.Pause()` / `scan.Continue()` / `scan.Stop()`;
- `scan.GetProgress()`;
- `scan.GetCategories()`.

The audited query shape is `{ name, minLevel, maxLevel, invType, class, subclass, quality }`. Aegis sends vanilla `QueryAuctionItems` calls page by page and waits for `AUCTION_ITEM_LIST_UPDATE`.

**Stability expectation: medium.** These are coherent, commented, upstream-tested internals, but they are not declared as a cross-addon public contract. The adapter probes function shape and pins the audited version in docs/source.

### Buy/search helpers

Useful symbols:

- `AegisExchange.buy.Search(text, callbacks)`;
- `buy.ClassOptions()`;
- `buy.SubclassOptions(class)`;
- `buy.SlotOptions(class, subclass)`;
- `buy.ClassName`, `SubclassName`, `SlotName`.

`buy.Search` rows include the live AH index, name, link, item id, stack count, quality, level, buyout, unit price, seller and time-left data for the current result page.

The category helpers are particularly useful for translating localized `GetItemInfo()` strings into the numeric indices expected by the vanilla AH API.

**Stability expectation: medium-low to medium.** They are implementation helpers, not a declared extension API. The Workbench only depends on the three option functions and probes all three.

### Item metadata normalizer

`AegisExchange.util.ItemInfo(link)` is intended to normalize the different `GetItemInfo` tuple shapes seen across the clients Aegis targets. The supplied 1.20.2 source also explicitly documents a second 1.12 constraint: `GetItemInfo` may return `nil` until the client-side item cache is warm, even for bag-driven workflows. Aegis itself falls back to the item-link name in some Sell/Buy paths when this happens. Similar Search needs more than the name (type/subtype/equipment slot/required level), so OctoTweaks warms a hidden bag tooltip and retries instead of treating the first `nil` as a permanent error.

The next OctoWoW runtime test exposed an additional incompatibility in Aegis 1.20.2: the target `Venomshroud Boots` normalized as `type=INVTYPE_FEET`, `subType=Interface\\Icons\\INV_Boots_09`, `minLevel=1`. That exact shift means the 1.20.2 normalizer's "last numeric return = stackCount" anchor is not safe for the tuple returned by this Octo client. OctoTweaks now validates Aegis' named result and, when it is structurally shifted, re-normalizes the raw client tuple by anchoring on the texture/equipment-location positions. Trailing client-specific returns are therefore ignored instead of shifting class/subclass/required level.

**Stability expectation: medium-low.** `util.ItemInfo` remains a useful first path, but runtime has shown that its cross-client heuristic is not sufficient by itself on this setup. All use remains behind `aegis.integration`, which owns cache warming, validation, defensive raw-tuple normalization, bounded retry, and diagnostics.

### Market database

Useful accessors:

- `AegisExchange.db.MarketValue(itemId)`;
- `AegisExchange.db.MinBuyout(itemId)`;
- `AegisExchange.db.GetVendor(itemId)` when present;
- `AegisExchange.db.SeenCount(itemId)` when present.

**Stability expectation: medium.** These are central readers used throughout Aegis. They are still accessed only through the adapter.

### Sell engine

Useful audited symbols include `sell.Suggest`, `sell.ScanItem`, `sell.Post`, `sell.StartPosting`, `sell.PostingActive`, `sell.CancelPosting`, `sell.CountInBags`, `sell.MaxStacks`, and the existing undercut/settings machinery.

**Stability expectation: medium for read-only suggestion/status, lower for posting orchestration.** Posting spends user assets and relies on live auction-slot/bag state. OctoTweaks does not reimplement those mechanics: it probes and delegates to Aegis' multi-stack `sell.StartPosting` engine, which already handles stack assembly, cap/availability checks, pacing, cancellation, and callbacks.

### Tooltip

`AegisExchange.tooltip.Extend(gtt, itemId, count)` exists and is the internal line writer, but Aegis also installs its own `GameTooltip` hooks.

The OctoWoW runtime test exposed a vanilla-client edge case: passing the full coloured `|c...|Hitem:...|h...|h|r` string from a collected AH row into native `GameTooltip:SetHyperlink` can raise `Unknown link type`. The adapter therefore prefers a verified live `SetAuctionItem` row and otherwise strips the link to its bare `item:...` payload before calling `SetHyperlink`, under `pcall`. If neither path is authoritative it falls back to the item name rather than surfacing a tooltip error.

**Stability expectation for direct `tooltip.Extend` calls: low/avoid.** Workbench still lets Aegis' installed hook add economics; only tooltip *opening* is normalized by the adapter.

### Aegis UI frames and grouped-result rendering internals

These were audited only to establish that grouped Buy results already exist. OctoTweaks does **not** bind to Aegis row frames, expansion tables, or window widgets.

**Stability expectation: low.** Treat presentation internals as private unless a future Aegis version exposes a supported extension point.

## OctoTweaks adapter capabilities

`aegis.integration` exposes `OctoTweaks.Aegis` and detects these named capabilities:

- `namespace`;
- `loaded`;
- `scan_start`;
- `scan_control`;
- `category_options`;
- `item_info`;
- `buy_search`;
- `market_db`;
- `sell_suggest`;
- `sell_posting`;
- `tooltip_extend`.

Minimum Workbench activation requires Aegis to have completed loading plus `scan_start`, `scan_control`, `category_options`, and Aegis' normalized `util.ItemInfo` reader (`item_info`). Market DB/tooltip helpers remain optional enhancements. `sell_posting` is separately probed: the Workbench can still search/price if posting is unavailable, but the POST control stays disabled.

Diagnostics:

```text
/otaegis
/otaegis status
/otaegis probe
/otaegis caps
```

The diagnostic output reports the detected Aegis version and each capability. Version 1.20.2 is **source-audited from the supplied installed addon** and the capabilities exercised by the current Workbench workflow are runtime-validated in OctoWoW. Unknown versions can still activate when the structural probe passes, but remain structurally compatible / unaudited until tested.

## `aegis.market_workbench` prototype

Status after phase-1 runtime validation: **IMPLEMENTED AND RUNTIME PASS ON AEGIS 1.20.2 FOR TARGET → SIMILAR SEARCH/POLL → TOOLTIP → SET → SUGGESTED PRICE → POST**.

Entry point:

```text
/otmarket
```

Prototype behavior:

1. Drop an actual bag item onto `Target Item`, or use `/otmarket target <bag> <slot>`. If the Aegis normalizer initially sees a cold item cache, the Workbench warms a hidden bag tooltip and retries for a bounded period rather than failing immediately.
2. The Target Item is retained independently from every search result/reference choice.
3. `SIMILAR SEARCH` derives AH class, subclass and equipment slot from the target and searches `requiredLevel +/- N`.
4. `Buyout only` and `Exact quality` are optional direct controls. `Exact quality` uses the server's minimum-quality narrowing plus an exact-quality post-filter on returned rows.
5. Aegis owns query pacing/page traversal. At each completed page, the adapter reads the already-loaded vanilla AH page to preserve the exact item link, stack, quality, unit/stack prices and seller for Workbench display.
6. Results are grouped by item id + displayed item name. A group can expand to individual listings.
7. Hovering a row uses the adapter's safe tooltip path: verified current AH rows use `SetAuctionItem`; stale/full links are reduced to a bare `item:...` payload before `SetHyperlink`, avoiding the 1.12 `Unknown link type` error while still letting Aegis add its economics.
8. `SET` stores the chosen auction as the **Reference Listing** only. It never replaces the Target Item.
9. Pricing supports `match`, `flat`, and `percent`. The default is flat 1 copper. Suggested price is per unit and clamped to at least 1 copper.
10. Direct posting is available from the right panel. The user chooses stack size, number of auctions, and 6h/24h/72h duration; `POST` uses Suggested Price as both per-unit start bid and buyout and delegates the actual stack assembly/submission to Aegis `sell.StartPosting`. `Cancel` stops only the Workbench-owned posting job.

Direct posting is intentionally narrow in this iteration: there is no `POST + NEXT`, automatic reference policy, or custom deposit/net-profit decision engine yet.

## Runtime validation evidence — Aegis 1.20.2

Phase 1 is now **PASS in OctoWoW** for the actual installed Aegis 1.20.2 build. The user confirmed the corrected Workbench:

- selects and preserves the Target Item with correct item metadata;
- runs Similar Search while the custom Aegis AH UI remains active;
- polls/collects the AH pages successfully;
- displays/interacts with grouped results;
- opens hover tooltips without the previous `Unknown link type` error;
- selects an independent Reference Listing through `SET`;
- computes the displayed Suggested Price;
- posts the Target Item successfully through the Aegis-backed `POST` path.

This PASS applies to the current manual-reference workflow and the Aegis 1.20.2 environment actually tested. It does not validate future automatic reference policies, `POST + NEXT`, background scanning, inventory analytics, or untested Aegis versions.

## Current prototype limitations

- Similar Search currently requires Aegis category helpers to resolve the target's localized class/subclass and, for equipment, slot exactly. The adapter now rejects structurally shifted Aegis item metadata and falls back to its own raw-tuple normalizer; `/otmarket itemprobe <bag> <slot>` prints raw returns 1-12 plus normalized values if another client shape appears.
- The AH-open check recognizes both the stock `AuctionFrame` and Aegis' custom `AegisExchangeFrame`. Aegis deliberately hides the Blizzard frame while keeping the server AH session alive, so users should not need to switch to Blizzard UI before Similar Search. Search still refuses to start if Aegis is scanning, paused, performing a Buy query, or posting.
- Workbench uses Aegis' all-pages scanner rather than the Buy tab's grouped UI. This is deliberate for the prototype because the Workbench needs a complete comparable set and a separate Reference Listing state; it is not intended as a replacement Buy browser.
- Group identity is item id plus displayed item name. Random-property edge cases require runtime observation before stronger identity semantics are chosen.
- No bid-only listing can become a pricing Reference Listing because there is no buyout/unit price to apply.
- Direct posting is implemented through Aegis, but deposit calculation in the Workbench, AH net/vendor-margin panel, `POST + NEXT`, automatic reference policy, inventory valuation, background scanning, and analytics are still deferred.
- Aegis' market-data freshness representation has not yet been exposed by the adapter; only current read accessors needed by the prototype are used.
- The Workbench is still a separate OctoTweaks window. Deep embedding as an Aegis sub-tab is deliberately deferred until the tooltip and posting paths are runtime-stable, because Aegis' UI tables/frames are private internals with lower stability than its sell/scan engines.

## Runtime regression procedure

The phase-1 path below has passed on the user's Aegis 1.20.2 setup. Re-run it after changes to the adapter, scanner coordination, tooltip path, pricing state, or posting bridge:

1. Enable Aegis: Exchange and OctoTweaks; open the Auction House.
2. Run `/ot status`; expect `aegis.integration = ENABLED` and `aegis.market_workbench = ENABLED`.
3. Run `/otaegis probe`; on the user's current setup expect Aegis **1.20.2** and true minimum Workbench capabilities. The old warning about an unaudited version should be replaced by a note that 1.20.2 was source-audited but runtime validation is still incomplete.
4. Stay on the normal **Aegis UI** (do not switch to Blizzard UI), run `/otmarket`, and drag a bag equipment item with an obvious class/subclass/slot and required level onto Target Item. A brief `Resolving Target Item metadata...` state is acceptable. If it still fails, run `/otmarket itemprobe <bag> <slot>` and capture every printed line.
5. Confirm the Target Item name/type/subtype/slot/required level are correct. In particular, an equipment slot token such as `INVTYPE_FEET` must appear as the slot, not as item type; an icon path must not appear as subtype.
6. Leave the default `+/- 2`, run `SIMILAR SEARCH` while Aegis UI remains active, and compare the status/search results with the expected AH category and level range. It must no longer refuse merely because Blizzard `AuctionFrame` is hidden.
7. Expand at least two groups. Verify parent total quantity/listing count and child seller/stack/unit/stack-price values against Aegis/vanilla AH data.
8. Hover a parent and a child. Confirm the correct tooltip opens with no `Unknown link type` error and Aegis economics appear once, not duplicated.
9. Press `SET` on a listing whose item is different from the Target Item. Confirm the right panel changes Reference but the Target Item does not change.
10. With a known reference price, test `flat` at `1`, `match`, and `percent` with a simple value such as `5`; verify Suggested Price arithmetic.
11. For a disposable/low-risk Target Item, set `Stack` and `Auctions` to small known values, choose duration, and press `POST`. Confirm Aegis posts the requested item at the displayed per-unit price and the Workbench progress/status matches the actual owned auction. Start with one auction for the first runtime test.
12. Start a second low-risk post and press `Cancel` while it is active; confirm only that Workbench posting job stops cleanly and no unrelated Aegis action is cancelled.
13. Start a normal Aegis scan, then try Similar Search. It should refuse rather than steal the query channel. Repeat with an Aegis scan paused; it should also refuse.
14. Start a Workbench Similar Search, press `Stop`, and confirm Aegis stops that Workbench-owned scan without a Lua error.
15. Close the Workbench during its own scan or Workbench-owned posting job and confirm its owned operation is cancelled cleanly.
16. Run `/otaegis probe` and `/otmarket status` after the tests and return any Lua errors plus the command output.

Phase-1 status is **PASS on Aegis 1.20.2**. New or materially changed paths must still be recorded separately as PENDING until exercised in OctoWoW.
