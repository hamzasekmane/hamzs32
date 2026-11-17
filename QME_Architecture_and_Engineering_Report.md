# QuantumMarketEngine (QME) — Architecture and Engineering Review

**Review date:** 2026-11-17
**Requested product:** MT5 indicator; analysis and display only, with no trade placement, modification, or closure
**Reviewed revision:** `7e0b7a4ce51757f09355560e612bc2405aa8e24f` (`Initial commit - QuantumMarketEngine`)

## Executive status

This report describes the state evidenced by the current checkout and work performed in this review. The MQL5 implementation is not present in the checkout, so no implementation-level architecture decision, source migration, or runtime fix can be claimed.

The repository currently tracks two MQL5 build logs but no `.mq5` or `.mqh` source files. The report that was present in the checkout described an Expert Advisor with risk and order execution; those claims did not match the requested indicator scope and could not be verified against source. This replacement deliberately avoids repeating unsupported implementation or verification claims.

## Repository evidence

Tracked project files at review start:

- `MQL5/build_ea.log`
- `MQL5/build_tests.log`
- `QME_Architecture_and_Engineering_Report.md`
- `compile_metaeditor.bat`
- `run_verification.bat`
- `verify_qme.py`
- `.sudo_as_admin_successful` (removed in this review)

No `MQL5/Include/QME/`, indicator entry point, or native test source is present. The two UTF-16LE logs reference a different Windows workspace and end with historical compiler summaries of zero errors and zero warnings. They are not a build of, or reproducible evidence for, the current checkout.

The logs describe an EA build and include a dependency chain through `RiskEngine` → `OrderManager` → MetaTrader `Trade.mqh`. This is an observed property of the historical logs, not a verified description of a current implementation. It conflicts with the requested no-trading indicator boundary and must not be carried forward as an accepted design.

## FSM and MTF decision

**Decision: deferred; no single source of truth has been selected or migrated.** The requested legacy M15 FSM and H4/H1-to-M5 MTF cascade are not available in the checked-out source. Selecting one, preserving public interfaces, and deleting the other without examining the implementation would be guesswork and could silently change indicator behavior.

**Assumption:** this branch’s tracked tree is the complete input available for this task. Historical build logs and the old architecture report are not sufficient substitutes for the missing source. Once the source is restored, the intended decision should be documented against its actual call sites and output interfaces before obsolete logic is removed.

## Requested data-readiness and analysis behavior

No code implementing these requirements is present to inspect or change:

- Check `SERIES_SYNCHRONIZED` for each required timeframe before analysis.
- Retry `CopyRates` and `CopyBuffer` after temporary history/synchronization failures, including error 4806.
- Re-attempt readiness from `OnTimer` without calculating until every required series and buffer is ready.
- Resolve the reported unknown bias and missing zones/targets.

Accordingly, there is no root cause established for the reported BTCUSD H1 “D1/H4 data not ready” display, `BarsCalculated() == -1`, unknown bias, or empty zones/targets. No fix or runtime test for those behaviors is claimed.

## Verification actually performed

- **Read-only inventory and report review:** completed.
- **Verification harness:** invoked with `python3 verify_qme.py` before hardening the harness. It reported all 14 expected module directories missing, then raised `FileNotFoundError` for `MQL5/Include/QME/Analysis/StructureAnalysis.mqh`. After adding the inventory gate, rerunning it reported the missing modules, printed `VERIFICATION BLOCKED`, and exited nonzero without a traceback. No source-level checks ran.
- **MetaEditor compile:** not run. The available build script is a Windows batch file, and this environment has no `cmd.exe`, Wine, or MetaEditor executable. The checked-in logs are historical only.
- **Runtime / Strategy Tester:** not run; no MQL5 sources or MT5 terminal/history feed are available here.

Status labels: **not compiled in this review; no current source-level verification; not runtime-tested.**

## Changes actually made in this review

- Added a fail-fast inventory gate to `verify_qme.py`, preventing an absent source tree from being mistaken for an empty successful include/dependency check or causing a later traceback.
- Added `.gitignore` entries for generated MetaTrader binaries/runtime files, local build logs, and OS noise.
- Removed the tracked `.sudo_as_admin_successful` artifact.
- Replaced unsupported prior architecture/verification statements with this evidence-based report and added `REVIEW_FINDINGS.md`.

No MQL5 behavior, public indicator interface, FSM, MTF loader, zone engine, or target engine was changed.

## Next verification steps once the source tree is restored

1. Restore the intended indicator sources, include tree, and MQL5 tests to this branch.
2. Run `python3 verify_qme.py` (or `run_verification.bat` on Windows) and resolve all source-level failures.
3. On a Windows machine with MT5 installed, run `compile_metaeditor.bat`; inspect both compiler logs and confirm the compiled entry point is an **indicator**, not an EA.
4. In MetaEditor, compile the indicator and native tests and retain the fresh build output.
5. In an MT5 terminal, attach the indicator to BTCUSD H1 and verify D1/H4 series readiness, error-4806 retry behavior, timer re-attempts, bias, zones, and targets. Repeat with representative XAUUSD, FX, and index symbols.
6. Run a Strategy Tester or controlled demo attachment to exercise loading transitions. Confirm no order API is called and no trades can be placed, modified, or closed.
7. Record the exact terminal/build/runtime outputs before marking any stage compiled, statically checked, or runtime-tested.
