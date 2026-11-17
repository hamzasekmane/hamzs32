import re
import unittest
from pathlib import Path

from qme_reference import (
    Bar, DISCOUNT, FVG, ORDER_BLOCK, SWEEP, Zone, add_premium_discount,
    aligned_bias, detect_fvg, detect_order_block, detect_sweep,
    explainable_score, grade, no_zone_reason, rr_passes, rr_ratio,
    strength, structural_target, tick_round,
)

ROOT = Path(__file__).resolve().parents[1]


class DataReadinessContractTests(unittest.TestCase):
    def test_mtf_loader_checks_sync_calculated_bars_and_4806(self):
        source = (ROOT / "MQL5/Include/QME/Data/MTFDataLoader.mqh").read_text()
        for token in ("SERIES_SYNCHRONIZED", "SeriesInfoInteger", "BarsCalculated",
                      "QME_HISTORY_NOT_FOUND 4806", "bars_error==QME_HISTORY_NOT_FOUND"):
            with self.subTest(token=token):
                self.assertIn(token, source)

    def test_rates_and_buffers_have_bounded_retries(self):
        source = (ROOT / "MQL5/Include/QME/Data/MTFDataLoader.mqh").read_text()
        self.assertIn("CopyRatesRetry", source)
        self.assertIn("CopyBuffer", source)
        self.assertIn("attempt<=QME_LOAD_ATTEMPTS", source)

    def test_copied_closed_rates_are_validated_and_sync_is_rechecked(self):
        source = (ROOT / "MQL5/Include/QME/Data/MTFDataLoader.mqh").read_text()
        self.assertIn("ValidateRates(tf,rates)", source)
        self.assertIn("rates[i-1].time<=rates[i].time", source)
        self.assertIn("bool ReadyNow(void)", source)
        self.assertIn("IsSynchronized(PERIOD_M5)", source)

    def test_sync_precedes_rate_and_buffer_loading(self):
        source = (ROOT / "MQL5/Include/QME/Data/MTFDataLoader.mqh").read_text()
        load_frame = source[source.index("bool LoadFrame("):source.index("public:")]
        self.assertLess(load_frame.index("IsSynchronized(tf)"), load_frame.index("CopyRatesRetry(tf"))
        self.assertLess(load_frame.index("CopyRatesRetry(tf"), load_frame.index("CopyOneBufferRetry(atr_handle"))

    def test_unused_accessors_and_wrappers_are_removed(self):
        loader = (ROOT / "MQL5/Include/QME/Data/MTFDataLoader.mqh").read_text()
        zones = (ROOT / "MQL5/Include/QME/Analysis/ZoneEngine.mqh").read_text()
        for source, obsolete in ((loader, ("bool Ready(void)", "HadHistory4806")),
                                 (zones, ("OrderBlockCount", "FVGCount", "SweepCount", "StrengthFor", "double RoundToTick("))):
            for token in obsolete:
                with self.subTest(token=token):
                    self.assertNotIn(token, source)

    def test_architecture_decision_and_migration_limit_are_documented(self):
        report = (ROOT / "QME_Architecture_and_Engineering_Report.md").read_text()
        for decision in (
            "Architecture decision: MTF is the sole analysis path",
            "Use one H4/H1-to-M5 multi-timeframe analysis cascade, with no persisted FSM decision state or parallel signal path.",
            "no legacy FSM source files or FSM transitions in the available tree",
            "The archived EA architecture document is a design narrative, not source",
            "Deliberately excluded: they are outside the indicator’s analysis-only boundary.",
            "remain blocked—not silently treated as complete",
        ):
            with self.subTest(decision=decision):
                self.assertIn(decision, report)

    def test_current_public_inputs_buffers_and_dashboard_contract(self):
        source = (ROOT / "MQL5/Indicators/QME/QME_Indicator.mq5").read_text()
        report = (ROOT / "QME_Architecture_and_Engineering_Report.md").read_text()
        inputs = re.findall(r"^input\s+(\w+)\s+(Inp\w+)\s*=\s*([^;]+);", source, re.MULTILINE)
        self.assertEqual(inputs, [
            ("int", "InpRequiredHistoryBars", "100"),
            ("int", "InpTimerSeconds", "2"),
            ("double", "InpMinimumScore", "65.0"),
            ("double", "InpMinimumRR", "1.50"),
            ("bool", "InpDrawZones", "true"),
        ])
        source_contract = (
            "#property indicator_buffers 2",
            '"QME demand signal"',
            '"QME supply signal"',
            "SetIndexBuffer(0,BuySignalBuffer,INDICATOR_DATA)",
            "SetIndexBuffer(1,SellSignalBuffer,INDICATOR_DATA)",
            'QuantumMarketEngine | Analysis only (no trading)',
            'Data: WAITING | ',
            'No calculation performed until required data is ready.',
            'Data: READY | Bias: ',
            'Entry probability score: ',
            ' | Entry gate: ',
            'Zone scan: ',
            'g_analysis.explanation',
            'g_analysis.reason',
        )
        for contract in source_contract:
            with self.subTest(contract=contract):
                self.assertIn(contract, source)
        documented_contract = (
            "InpRequiredHistoryBars = 100", "InpTimerSeconds = 2",
            "InpMinimumScore = 65.0", "InpMinimumRR = 1.50", "InpDrawZones = true",
            "BuySignalBuffer[]", "QME demand signal", "SellSignalBuffer[]", "QME supply signal",
            "Data: WAITING | <reason>", "No calculation performed until required data is ready.",
            "Data: READY | Bias: <bias> | Zones: <count>",
            "Entry probability score: <score>/100 | RR: <ratio> | Entry gate: <status>",
            "explanation, veto reason, and `Zone scan: <reason>`",
        )
        for contract in documented_contract:
            with self.subTest(documented_contract=contract):
                self.assertIn(contract, report)
        self.assertIn("Historical interface preservation remains unverified", report)

    def test_timer_retries_and_calculation_is_gated(self):
        source = (ROOT / "MQL5/Indicators/QME/QME_Indicator.mq5").read_text()
        self.assertIn("EventSetTimer", source)
        self.assertIn("void OnTimer(void)", source)
        self.assertIn("g_data.Refresh()", source)
        orchestrator = source[source.index("void UpdateAnalysis(void)"):source.index("int OnInit(void)")]
        self.assertLess(orchestrator.index("if(!g_data.ReadyNow())"), orchestrator.index("g_zones.Build(g_data)"))
        self.assertLess(orchestrator.index("if(!g_data.ReadyNow())"), orchestrator.index("g_signals.Evaluate("))
        calculate = source[source.index("int OnCalculate("):]
        self.assertIn("UpdateAnalysis();", calculate)
        self.assertEqual(source.count("g_data.ReadyNow()"), 1)
        self.assertIn("No calculation performed until required data is ready", source)

    def test_every_no_entry_path_has_a_specific_reason(self):
        source = (ROOT / "MQL5/Include/QME/Analysis/SignalEngine.mqh").read_text()
        for reason in ("quote is unavailable", "zones.Reason()", "H4 and H1", "no ",
                       "confirming closed M5", "no opposing zone", "RR ", "score "):
            with self.subTest(reason=reason):
                self.assertIn(reason, source)

    def test_indicator_has_no_trade_api(self):
        files = list((ROOT / "MQL5").rglob("*.mq5")) + list((ROOT / "MQL5").rglob("*.mqh"))
        source = "\n".join(p.read_text(errors="ignore") for p in files)
        for forbidden in ("OrderSend(", "CTrade", ".Buy(", ".Sell(", "PositionModify(", "PositionClose("):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)


class ZoneDetectionTests(unittest.TestCase):
    def test_bullish_and_bearish_fvg_levels_are_precise(self):
        bullish = detect_fvg(Bar(99, 100, 98, 99), Bar(103, 105, 102, 104), 1, 2, 0.01, 0.01)
        bearish = detect_fvg(Bar(102, 104, 101, 103), Bar(98, 99, 96, 97), -1, 2, 0.01, 0.01)
        self.assertEqual((bullish.low, bullish.high), (100, 102))
        self.assertEqual((bearish.low, bearish.high), (99, 101))
        self.assertEqual(bullish.features, FVG)
        self.assertEqual(bearish.features, FVG)

    def test_fvg_threshold_uses_atr_tick_and_point(self):
        older = Bar(99, 100, 98, 99)
        too_small = Bar(101, 103, 100.5, 102)
        enough = Bar(102.3, 104, 102.3, 103)
        self.assertIsNone(detect_fvg(older, too_small, 1, 10, 0.01, 0.01))
        self.assertIsNotNone(detect_fvg(older, enough, 1, 10, 0.01, 0.01))

    def test_order_block_requires_opposing_base_and_atr_displacement(self):
        base = Bar(10, 10.2, 9.7, 9.8)
        impulse = Bar(9.9, 11.2, 9.8, 10.8)
        self.assertEqual(detect_order_block(base, impulse, 1, 1), Zone(9.7, 10.2, 1, ORDER_BLOCK))
        weak = Bar(9.9, 10.3, 9.8, 10.25)
        self.assertIsNone(detect_order_block(base, weak, 1, 1))

    def test_bullish_and_bearish_liquidity_sweeps(self):
        prior = [Bar(10, 11, 9, 10), Bar(10, 10.5, 9.5, 10)]
        bull = detect_sweep(Bar(9.5, 10.2, 8.8, 9.7), prior, 1)
        bear = detect_sweep(Bar(10, 11.4, 9.8, 10.8), prior, -1)
        self.assertEqual((bull.low, bull.high), (8.8, 9))
        self.assertEqual((bear.low, bear.high), (11, 11.4))

    def test_premium_discount_strength_and_grades(self):
        discount = add_premium_discount(Zone(90, 92, 1, ORDER_BLOCK), 100)
        self.assertTrue(discount.features & DISCOUNT)
        self.assertEqual(strength(discount), 50)
        self.assertEqual(grade(discount), "C")
        strong = Zone(90, 92, 1, ORDER_BLOCK | FVG | SWEEP | DISCOUNT)
        self.assertEqual(strength(strong), 100)
        self.assertEqual(grade(strong), "A")

    def test_tick_rounding_is_symbol_agnostic(self):
        for price, tick, point in ((67234.57, 0.01, 0.01), (2350.17, 0.1, 0.01),
                                   (1.083456, 0.00001, 0.00001), (18450.37, 0.25, 0.1)):
            rounded = tick_round(price, tick, point)
            self.assertAlmostEqual(rounded / max(tick, point), round(rounded / max(tick, point)))


class EntryDecisionTests(unittest.TestCase):
    def test_h4_h1_alignment_is_the_single_bias_source(self):
        self.assertEqual(aligned_bias(1, 1), 1)
        self.assertEqual(aligned_bias(-1, -1), -1)
        self.assertEqual(aligned_bias(1, -1), 0)
        self.assertEqual(aligned_bias(0, 1), 0)

    def test_target_prefers_nearest_opposing_zone_then_h4_swing(self):
        zones = [Zone(110, 112, -1, FVG), Zone(104, 105, -1, ORDER_BLOCK)]
        self.assertEqual(structural_target(1, 100, zones, []), 104)
        self.assertEqual(structural_target(1, 100, [], [Bar(100, 108, 95, 103), Bar(103, 106, 99, 105)]), 106)
        self.assertIsNone(structural_target(1, 120, [], [Bar(100, 110, 90, 105)]))

    def test_explainable_score_has_component_bounded_result(self):
        zone = Zone(100, 101, 1, ORDER_BLOCK | FVG | SWEEP | DISCOUNT)
        self.assertEqual(explainable_score(zone, True, True), 100)
        self.assertLess(explainable_score(zone, False, False), 100)

    def test_rr_gate_passes_and_vetoes(self):
        self.assertAlmostEqual(rr_ratio(100, 98, 104), 2.0)
        self.assertTrue(rr_passes(100, 98, 103, 1.5))
        self.assertFalse(rr_passes(100, 98, 102, 1.5))

    def test_no_zones_reason_names_all_detection_families(self):
        reason = no_zone_reason(0, 0, 0, 0)
        for term in ("No zones", "OB", "FVG", "liquidity sweep"):
            self.assertIn(term, reason)
        self.assertEqual(no_zone_reason(1, 1, 0, 0), "Zones available")


if __name__ == "__main__":
    unittest.main()
