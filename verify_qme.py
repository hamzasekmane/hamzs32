#!/usr/bin/env python3
"""QME indicator source and regression verification (host-side; not MetaEditor)."""
from __future__ import annotations

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MQL5 = ROOT / "MQL5"
INCLUDE = MQL5 / "Include" / "QME"
REQUIRED_DIRS = [
    INCLUDE / "Core", INCLUDE / "Data", INCLUDE / "Analysis",
    MQL5 / "Indicators" / "QME", MQL5 / "Scripts" / "QME",
]
REQUIRED_FILES = [
    INCLUDE / "Core" / "QMETypes.mqh",
    INCLUDE / "Data" / "MTFDataLoader.mqh",
    INCLUDE / "Analysis" / "ZoneEngine.mqh",
    INCLUDE / "Analysis" / "SignalEngine.mqh",
    MQL5 / "Indicators" / "QME" / "QME_Indicator.mq5",
    MQL5 / "Scripts" / "QME" / "QME_RunTests.mq5",
    ROOT / "Tests" / "test_qme_features.py",
]


def header(title: str) -> None:
    print("\n" + "=" * 72 + f"\n {title}\n" + "=" * 72)


def test_inventory() -> bool:
    header("TEST 1: QME indicator inventory")
    missing = [str(path.relative_to(ROOT)) for path in REQUIRED_DIRS + REQUIRED_FILES if not path.exists()]
    if missing:
        for item in missing:
            print(f"  [FAIL] Missing {item}")
        return False
    print("  [PASS] Indicator, MTF loader, analysis modules, native runner, and host tests found.")
    return True


def test_include_guards() -> bool:
    header("TEST 2: Include guards")
    files = list(INCLUDE.rglob("*.mqh"))
    if not files:
        print("  [FAIL] No QME headers found.")
        return False
    seen: dict[str, Path] = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        opening = re.search(r"^#ifndef\s+(\w+)\s*$", text, re.M)
        define = re.search(r"^#define\s+(\w+)\s*$", text, re.M)
        if not opening or not define or opening.group(1) != define.group(1):
            print(f"  [FAIL] Guard missing or mismatched: {path.relative_to(ROOT)}")
            return False
        name = opening.group(1)
        if name in seen:
            print(f"  [FAIL] Duplicate guard {name}: {seen[name]} and {path}")
            return False
        seen[name] = path
    print(f"  [PASS] {len(files)} headers have unique matching guards.")
    return True


def test_dependency_graph() -> bool:
    header("TEST 3: QME include dependency graph")
    files = {p.relative_to(INCLUDE).as_posix(): p for p in INCLUDE.rglob("*.mqh")}
    graph: dict[str, list[str]] = defaultdict(list)
    include_re = re.compile(r"^\s*#include\s+[\"<]([^\">]+)[\">]", re.M)
    for rel, path in files.items():
        for target in include_re.findall(path.read_text(encoding="utf-8")):
            target = target.replace("\\", "/")
            if not target.startswith("QME/"):
                continue
            child = target[4:]
            if child in files:
                graph[rel].append(child)
            else:
                print(f"  [FAIL] Unresolved QME include in {rel}: {target}")
                return False
    state: dict[str, int] = {}

    def visit(node: str) -> bool:
        state[node] = 1
        for child in graph[node]:
            if state.get(child) == 1:
                print(f"  [FAIL] Include cycle through {node} -> {child}")
                return False
            if state.get(child, 0) == 0 and not visit(child):
                return False
        state[node] = 2
        return True

    if not all(state.get(node, 0) or visit(node) for node in files):
        return False
    print(f"  [PASS] {len(files)} QME headers form an acyclic include graph.")
    return True


def test_architecture_contract() -> bool:
    header("TEST 4: Indicator safety and MTF feature contract")
    source_files = list(MQL5.rglob("*.mq5")) + list(INCLUDE.rglob("*.mqh"))
    source = "\n".join(path.read_text(encoding="utf-8") for path in source_files)
    loader = (INCLUDE / "Data" / "MTFDataLoader.mqh").read_text(encoding="utf-8")
    indicator = (MQL5 / "Indicators" / "QME" / "QME_Indicator.mq5").read_text(encoding="utf-8")
    zones = (INCLUDE / "Analysis" / "ZoneEngine.mqh").read_text(encoding="utf-8")
    signals = (INCLUDE / "Analysis" / "SignalEngine.mqh").read_text(encoding="utf-8")
    checks = {
        "series synchronization": "SERIES_SYNCHRONIZED" in loader and "SeriesInfoInteger" in loader,
        "BarsCalculated and error 4806": "BarsCalculated" in loader and "QME_HISTORY_NOT_FOUND 4806" in loader,
        "CopyRates and CopyBuffer retries": "CopyRatesRetry" in loader and "CopyBuffer" in loader and "QME_LOAD_ATTEMPTS" in loader,
        "timer readiness retry": "EventSetTimer" in indicator and "void OnTimer(void)" in indicator and "g_data.Refresh()" in indicator,
        "single centralized readiness gate": indicator.count("g_data.ReadyNow()") == 1 and "data.ReadyNow()" not in zones and "data.ReadyNow()" not in signals,
        "order blocks": "QME_ZONE_ORDER_BLOCK" in zones,
        "fair value gaps": "QME_ZONE_FVG" in zones,
        "liquidity sweeps": "QME_ZONE_SWEEP" in zones,
        "premium/discount": "QME_ZONE_DISCOUNT" in zones,
        "zone grading": "string Grade(" in zones and "QMEZoneStrength" in zones and "QMEZoneGrade" in zones,
        "explainable score and RR gate": "result.explanation" in signals and "minimum_rr" in signals,
        "why-no-zones reason": "No zones:" in zones and "zones.Reason()" in signals,
        "single H4/H1-to-M5 signal path": "Trend(PERIOD_H4,data)" in signals and "Trend(PERIOD_H1,data)" in signals and "M5Confirmed" in signals,
    }
    ok = True
    for label, passed in checks.items():
        print(f"  [{'PASS' if passed else 'FAIL'}] {label}")
        ok &= passed
    forbidden = ("OrderSend(", "CTrade", ".Buy(", ".Sell(", "PositionModify(", "PositionClose(")
    violations = [token for token in forbidden if token in source]
    if violations:
        print(f"  [FAIL] Trading API references found: {violations}")
        ok = False
    else:
        print("  [PASS] No trade placement/modification/closure APIs in QME source.")
    symbol_constants = re.search(r"BTCUSD|XAUUSD|EURUSD|NAS100|US30", source, re.I)
    if symbol_constants:
        print("  [FAIL] Per-symbol constant detected in source.")
        ok = False
    else:
        print("  [PASS] No hard-coded instrument names.")
    return bool(ok)


def clean_code(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', text)


def test_delimiters() -> bool:
    header("TEST 5: MQL delimiter integrity")
    failed = False
    for path in list(MQL5.rglob("*.mq5")) + list(MQL5.rglob("*.mqh")):
        text = clean_code(path.read_text(encoding="utf-8"))
        for left, right in (("{", "}"), ("(", ")"), ("[", "]")):
            if text.count(left) != text.count(right):
                print(f"  [FAIL] {path.relative_to(ROOT)}: {left}{right} count mismatch")
                failed = True
    if not failed:
        print("  [PASS] MQL source delimiter counts are balanced.")
    return not failed


def test_feature_scenarios() -> bool:
    header("TEST 6: Zone, score, RR, and regression scenarios")
    tests = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(ROOT / "Tests"), "-p", "test_*.py", "-v"],
        cwd=ROOT, text=True, capture_output=True,
    )
    print(tests.stdout, end="")
    print(tests.stderr, end="")
    print("  [PASS] Feature scenario tests passed." if tests.returncode == 0 else "  [FAIL] Feature scenario tests failed.")
    return tests.returncode == 0


def main() -> int:
    print("\n# QUANTUMMARKETENGINE (QME) - INDICATOR VERIFICATION")
    if not test_inventory():
        print("\n[BLOCKED] Restore the required QME indicator sources before running source checks.")
        return 1
    results = [test_include_guards(), test_dependency_graph(), test_architecture_contract(),
               test_delimiters(), test_feature_scenarios()]
    print("\nSTATUS: " + ("ALL HOST CHECKS PASSED (MetaEditor/runtime not implied)." if all(results)
                        else "ONE OR MORE CHECKS FAILED."))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
