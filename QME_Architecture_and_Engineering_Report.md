# QuantumMarketEngine (QME) — Architecture and Engineering Report

**Review/update date:** 2026-11-17
**Product boundary:** MT5 indicator; analysis and chart output only. QME contains no order placement, modification, or close calls.
**Status:** source implementation added in this branch; host checks pass. MetaEditor compilation and terminal runtime remain unverified.

## Important reconstruction assumption

At the start of this work, the tracked repository had no `.mq5` or `.mqh` source—only historical EA/test compiler logs, scripts, and an architecture document describing a trading EA. There was no source from which to preserve public inputs/buffers, migrate an existing FSM, or safely delete legacy code. The stale EA/test compiler logs were removed rather than carried forward as evidence for the new indicator.

To make progress within the requested indicator scope, this branch now establishes a new analysis-only indicator implementation and explicit interfaces. This is **not a source-to-source migration** of the missing implementation. Compatibility with its former public interfaces and behavior cannot be claimed. The old compile logs are historical evidence only and are not used as source.

## Architecture decision: one MTF plan cascade

The new indicator uses the MTF cascade as its single analysis source of truth:

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

There is no legacy M15 FSM implementation in the restored/current source tree, so no FSM code could be migrated or deleted. No second signal path is implemented. If the original FSM sources are later supplied, this decision and the public interface compatibility must be reviewed against them before merging them into this implementation.

## Data readiness and retry behavior

`MQL5/Include/QME/Data/MTFDataLoader.mqh` owns all required H4, H1, and M5 series/buffer access. For each timeframe it:

1. Calls `SeriesInfoInteger(..., SERIES_SYNCHRONIZED, ...)` before copying or analysis.
2. Loads a fixed number of closed rates with bounded `CopyRates` retries.
3. Checks each ATR/EMA handle with `BarsCalculated`; negative/insufficient counts defer analysis. Error 4806 is retained in the diagnostic reason.
4. Retries each `CopyBuffer` read and reports which timeframe/buffer failed.
5. Reports readiness only after all three timeframes, their rates, ATR, and EMA buffers are valid.

The indicator starts a timer (`InpTimerSeconds`, default two seconds). Each `OnTimer` calls `Refresh` again, allowing history synchronization to progress without a busy wait. `OnCalculate` and the analysis routine gate all signal/zone calculation on `ReadyNow()`, which rechecks H4/H1/M5 synchronization against the cached loaded data. Before readiness, the dashboard says calculation is deferred and the signal buffers are empty.

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
- `Tests/test_qme_features.py` has 18 host tests for synchronization/retry/readiness contracts, no-trade safety, zone features, symbol-agnostic tick quantization, score/RR, and no-entry explanations.
- `verify_qme.py` checks source inventory, include guards and cycles, indicator safety, data-readiness contracts, zone/scoring requirements, delimiters, and the host test suite.

**Run in this environment:** `python3 -m unittest discover -s Tests -p 'test_*.py' -v` passed 18 tests. `python3 verify_qme.py` passed all host checks. These are host/static checks, not MQL compilation or MT5 runtime verification.

**Not run:** MetaEditor compile, MT5 Strategy Tester, live/demo terminal. The current environment does not provide MetaEditor/Windows MT5. No claim of compiled or runtime-tested behavior is made.

## Current public inputs and outputs

New inputs: `InpRequiredHistoryBars`, `InpTimerSeconds`, `InpMinimumScore`, `InpMinimumRR`, and `InpDrawZones`. The indicator exposes two arrow buffers for accepted buy/sell analysis signals, dashboard text via `Comment`, zone rectangles, and a structural target line. Because the original source/interfaces were absent, these are newly established—not verified-compatible—interfaces.

## Terminal verification steps

1. Open `MQL5/Indicators/QME/QME_Indicator.mq5` in MetaEditor and compile with F7. Resolve any terminal/compiler-specific diagnostics before runtime use.
2. Compile `MQL5/Scripts/QME/QME_RunTests.mq5`; run it from MT5 and verify all native assertions pass.
3. Attach the indicator to BTCUSD H1 after the terminal has loaded H4/H1/M5 history. Inspect the dashboard and Experts/Journal logs while data synchronizes; confirm retries, timer readiness, no pre-readiness calculations, and a specific no-entry reason when gated.
4. Check zone boundaries against symbol tick size, grades, score components, target, and RR. Repeat on XAUUSD, a forex pair, and an index.
5. Verify the indicator is analysis-only: it must not issue, modify, or close trades. Test the history-not-ready case by attaching before the required timeframe history has finished loading, then confirm the timer recovers once data is available.
6. Record actual compiler and terminal output before changing status to compiled or runtime-tested.
