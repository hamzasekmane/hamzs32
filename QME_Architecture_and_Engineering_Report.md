# QuantumMarketEngine (QME) — Architecture and Engineering Report

**Review/update date:** 2026-11-17
**Product boundary:** MT5 indicator; analysis and chart output only. QME contains no order placement, modification, or close calls.
**Verification status:** **Compiled: no** (MetaEditor unavailable); **statically checked: yes** (host verifier and 21 Python scenarios passed); **runtime-tested: no** (MT5 cannot be run in this environment).

## Important reconstruction assumption

At the pre-implementation revision (`7e0b7a4`), the tracked repository had no `.mq5` or `.mqh` source—only historical EA/test compiler logs, scripts, and an architecture document describing a trading EA. The initial tree and the inspected implementation-PR history contain no FSM implementation or public MQL5 interface to preserve. The stale EA/test compiler logs were removed rather than carried forward as evidence for the new indicator.

The indicator files in the current tree were introduced afterward as a scoped analysis-only reconstruction with explicit new interfaces. This is **not a source-to-source migration** of a legacy implementation. Compatibility with unknown former inputs, buffers, dashboard fields, transitions, or behavior cannot be claimed. Historical compile logs are not source and are not used to infer those details.

## Architecture decision: MTF is the sole analysis path

**Decision:** Use one H4/H1-to-M5 multi-timeframe analysis cascade, with no persisted FSM decision state or parallel signal path. Do not model an unknown legacy FSM from log output. This keeps the indicator analysis-only and prevents independent strategies from duplicating readiness checks or disagreeing about bias, zones, and entry vetoes.

The current responsibility mapping is:

| Analysis responsibility | Current owner and boundary |
|---|---|
| Synchronization, closed-rate/buffer loading, retry and readiness | `CQMEDataLoader::Refresh` and `ReadyNow` in `MQL5/Include/QME/Data/MTFDataLoader.mqh` |
| H4/H1 trend context and directional bias | `CQMESignalEngine::Trend` and `Bias` |
| H4/H1 zone construction | `CQMEZoneEngine::Build` |
| M5 confirmation, zone selection, score, stop/target, RR and veto reason | `CQMESignalEngine::Evaluate` |
| Shared readiness gate and chart/buffer presentation | `UpdateAnalysis` in `MQL5/Indicators/QME/QME_Indicator.mq5` |

```text
H4 + H1 closed rates, ATR and EMA context
                 │
                 ├── bias alignment and demand/supply zones
                 ▼
M5 closed rates, ATR and EMA buffers
                 │
                 ├── entry confirmation, score, stop, target and RR gate
                 ▼
Dashboard, chart zones/target, and indicator signal buffers
```

### Migration and deletion disposition

For the code that exists, the MTF path is consolidated rather than run beside an FSM: `OnInit`, `OnTimer`, and `OnCalculate` all call `UpdateAnalysis`; the single readiness gate precedes both engines. The zone and signal engines own their distinct analysis responsibilities, and the loader owns MTF data access. The cleanup removed obsolete duplicate gates, unused loader state/getters, per-feature count getters, and trivial zone wrappers while retaining error-4806 diagnostics and zone feature counts in their diagnostic reasons.

There are **no legacy FSM source files or FSM transitions in the available tree to migrate or delete**. The archived EA architecture document is a design narrative, not source: it describes market-data, risk, execution, and persistence subsystems but supplies no FSM transition table or indicator interface. The migration disposition is therefore:

| Legacy/design responsibility | Disposition in the analysis-only indicator |
|---|---|
| MTF series synchronization, closed data and readiness | Reimplemented at the `CQMEDataLoader` boundary with retries and diagnostics; this is not a source-level port. |
| Strategy/FSM transitions and legacy signal decisions | Not recoverable from the available design document. The current `ZoneEngine`/`SignalEngine` MTF rules are the documented reconstruction, not verified equivalents of missing transitions. |
| Order execution, duplicate-order prevention, risk authorization and persisted execution hashes | Deliberately excluded: they are outside the indicator’s analysis-only boundary. No trade APIs or execution state are retained. |
| Legacy build logs | Removed; they are not source and are not treated as compile evidence for this implementation. |

For current code, the clean consolidation and removal of duplicate readiness gates, unused loader state/getters, per-feature getters, and trivial wrappers are complete as described above. The concrete FSM-to-MTF source migration and deletion of legacy FSM artifacts remain blocked—not silently treated as complete. If the source or an authoritative interface specification becomes available, map actual transitions and outputs against the responsibility table, port only in-scope analysis behavior, verify the public interface, then delete the superseded path and its tests. Do not add a parallel path or claim compatibility until that review is completed.

## Data readiness and retry behavior

`MQL5/Include/QME/Data/MTFDataLoader.mqh` owns all required H4, H1, and M5 series/buffer access. For each timeframe it:

1. Calls `SeriesInfoInteger(..., SERIES_SYNCHRONIZED, ...)` before copying or analysis.
2. Loads a fixed number of closed rates with bounded `CopyRates` retries.
3. Checks each ATR/EMA handle with `BarsCalculated`; negative/insufficient counts defer analysis. Error 4806 is retained in the diagnostic reason.
4. Retries each `CopyBuffer` read and reports which timeframe/buffer failed.
5. Reports readiness only after all three timeframes, their rates, ATR, and EMA buffers are valid.

The indicator starts a timer (`InpTimerSeconds`, default two seconds). Each `OnTimer` calls `Refresh` again, allowing history synchronization to progress without a busy wait. The shared `UpdateAnalysis` orchestration performs one `ReadyNow()` gate before calling the zone and signal engines; `ReadyNow()` rechecks H4/H1/M5 synchronization against the cached loaded data. `OnInit`, `OnTimer`, and `OnCalculate` all use this orchestration, so no analysis layer is entered before readiness. Before readiness, the dashboard says calculation is deferred and the signal buffers are empty. The duplicate gates inside the zone and signal engines were removed; their caller contract is documented at each public analysis method.

Retries are bounded within each event and recur on subsequent timer events. No `Sleep` is used from indicator code.

## Zone engine

`MQL5/Include/QME/Analysis/ZoneEngine.mqh` scans closed H4/H1 candles and rounds resulting price boundaries to the symbol’s trade tick size (falling back to point size).

- **Order blocks:** last opposing candle before a displacement of at least 0.45 ATR.
- **Fair value gaps:** three-candle imbalance with gap at least 0.10 ATR and no less than tick/point resolution.
- **Liquidity sweeps:** closed candle takes a prior 12-bar range extreme and closes back inside.
- **Premium/discount:** zone center relative to the scanned timeframe’s recent range midpoint.
- Nearby same-direction zones are merged using an ATR-normalized tolerance; the component flags are retained.
- Strength is an explainable 0–100 grade: order block 35, FVG 25, sweep 25, premium/discount 15. Grades are A (80+), B (60+), C (40+), and D (below 40).

The ratios are shared across symbols; absolute price increments are derived from tick size, point, and timeframe ATR. These rules are deterministic heuristics, not claims of institutional intent or measured trading performance.

## Entry score, target, and no-entry diagnostics

`MQL5/Include/QME/Analysis/SignalEngine.mqh` requires aligned H4/H1 EMA/close trends, a nearby zone in the bias direction, and a confirming closed M5 candle. The 0–100 **entry probability/confluence score** is a weighted, explainable heuristic:

- aligned H4/H1 bias: 20 points
- zone strength: up to 25
- FVG: 15
- liquidity sweep: 15
- premium/discount location: 10
- closed M5 confirmation: 15

It is not statistically calibrated and must not be interpreted as a win probability until separately validated. The user-configurable minimum score defaults to 65. Stop distance uses the selected zone boundary plus 0.10 M5 ATR (at least one tick); target is the nearest opposing zone or a valid H4 range extreme. Entries are vetoed when RR is below `InpMinimumRR` (default 1.50).

Every veto populates `QMEAnalysis.reason`, including unavailable quote/data, no qualifying zones (with OB/FVG/sweep counts), unaligned bias, no nearby zone, missing M5 confirmation, no structural target, invalid stop, low RR, and low score. The dashboard includes the reason, zone count, score breakdown, RR, and selected target. Zone rectangles and the target line are chart objects; signal buffers are analysis outputs only.

## Tests and verification

- `MQL5/Scripts/QME/QME_RunTests.mq5` has native test cases for FVG boundaries/thresholds, order-block displacement, sweeps, zone grade, score, RR, and tick rounding.
- `Tests/test_qme_features.py` has 21 host tests for synchronization/retry/readiness contracts, the documented architecture/migration disposition, the current public interface contract, no-trade safety, removal of obsolete accessors/wrappers, zone features, symbol-agnostic tick quantization, score/RR, and no-entry explanations.
- `verify_qme.py` checks source inventory, include guards and cycles, indicator safety, data-readiness contracts (including one centralized readiness gate), zone/scoring requirements, delimiters, and the host test suite.
- Dead state (`m_error_4806`), unused readiness/history and per-feature count getters, trivial zone wrappers, and redundant readiness checks were removed. Error 4806 remains visible in the loader's diagnostic reason where each data request fails; feature counts remain part of the zone-engine reason string.

**Statically checked:** `python3 -m unittest discover -s Tests -p 'test_*.py' -v` passed 21 tests, and `python3 verify_qme.py` passed all host checks. `git diff --check` also passed. These host checks do not parse or compile MQL5.

- **Compiled:** No. MetaEditor is unavailable in this Linux environment.
- **Runtime-tested:** No. MT5 cannot be run in this environment; the Strategy Tester and live/demo terminal were not run.

## Current public interface contract

The following is the public surface of the **current MTF reconstruction**, to preserve unless an intentional, documented change is approved. It is not evidence of compatibility with a missing legacy FSM indicator; the pre-reconstruction tree had no source or interface definitions to compare.

| Kind | Current contract | Purpose |
|---|---|---|
| Input | `InpRequiredHistoryBars = 100` | Minimum requested history depth (loader enforces its own minimum). |
| Input | `InpTimerSeconds = 2` | Retry cadence for MTF history readiness. |
| Input | `InpMinimumScore = 65.0` | Minimum confluence score for an analysis signal. |
| Input | `InpMinimumRR = 1.50` | Minimum risk/reward gate. |
| Input | `InpDrawZones = true` | Toggle zone rectangles. |
| Indicator buffers | Buffer 0 `BuySignalBuffer[]`, label `QME demand signal`; buffer 1 `SellSignalBuffer[]`, label `QME supply signal`. | Arrow values for accepted buy/sell analysis signals; never trade instructions. |
| Dashboard | Title `QuantumMarketEngine | Analysis only (no trading)`; waiting fields `Data: WAITING | <reason>` and `No calculation performed until required data is ready.` | Readiness/defer status. |
| Dashboard | Ready fields `Data: READY | Bias: <bias> | Zones: <count>`, `Entry probability score: <score>/100 | RR: <ratio> | Entry gate: <status>`, followed by explanation, veto reason, and `Zone scan: <reason>`. | Current analysis and diagnostic display. |
| Chart objects | `QME_MTF_zone_<index>` rectangles and `QME_MTF_target` line. | Visual zone and target output. |

No public input, buffer index/label, or dashboard field is changed by this architecture-documentation update. The current names and key labels are regression-tested. Historical interface preservation remains unverified until the original `.mq5`/`.mqh` source or an authoritative interface specification is supplied.

## Terminal verification steps

1. In MT5, choose **File → Open Data Folder**. Copy this repository’s `MQL5/Include/QME` into `<data-folder>/MQL5/Include/QME`, `MQL5/Indicators/QME` into `<data-folder>/MQL5/Indicators/QME`, and `MQL5/Scripts/QME` into `<data-folder>/MQL5/Scripts/QME`.
2. On Windows, from the repository root run `compile_metaeditor.bat`. It compiles the indicator and native test script and checks that both logs report `0 errors, 0 warnings`. If MetaEditor is installed outside the script’s standard paths, open `QME_Indicator.mq5` and `QME_RunTests.mq5` manually in MetaEditor and press F7 for each; inspect the fresh compile results.
3. In MT5, refresh Navigator, find `QME_RunTests` under Scripts, run it, and verify the Experts log reports all assertions passed.
4. Attach `QME_Indicator` to BTCUSD H1. Ensure H4/H1/M5 history is available. Inspect the chart dashboard and Experts/Journal during initial history loading; confirm it waits without calculating, retries on timer, then reports data ready or a specific no-entry reason.
5. Check tick-aligned zone boundaries, grades, score breakdown, target, and RR. Repeat on XAUUSD, a forex pair, and an index; record the broker symbol names and tick sizes used.
6. Confirm the indicator is analysis-only and issues no orders. To exercise recovery, attach before required history is fully loaded, observe the waiting/retry state, then confirm readiness after the terminal loads history.
7. Save the compiler logs, native test output, and chart/Journal observations. Only then update the status to compiled or runtime-tested; do not infer those statuses from the host checks.
