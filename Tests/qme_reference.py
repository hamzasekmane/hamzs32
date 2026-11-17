"""Small, symbol-agnostic reference model used by QME regression tests."""
from dataclasses import dataclass

ORDER_BLOCK = 1
FVG = 2
SWEEP = 4
DISCOUNT = 8

@dataclass(frozen=True)
class Bar:
    open: float
    high: float
    low: float
    close: float
    time: int = 0

@dataclass(frozen=True)
class Zone:
    low: float
    high: float
    direction: int
    features: int


def tick_round(price: float, tick_size: float, point: float) -> float:
    tick = max(tick_size, point)
    if tick <= 0:
        raise ValueError("tick size and point must be positive")
    return round(round(price / tick) * tick, 12)


def detect_fvg(older: Bar, newer: Bar, direction: int, atr: float,
               tick_size: float, point: float, min_gap_atr: float = 0.10):
    threshold = max(max(tick_size, point), atr * min_gap_atr)
    if direction > 0 and newer.low - older.high >= threshold:
        return Zone(older.high, newer.low, 1, FVG)
    if direction < 0 and older.low - newer.high >= threshold:
        return Zone(newer.high, older.low, -1, FVG)
    return None


def detect_order_block(base: Bar, impulse: Bar, direction: int, atr: float):
    if direction > 0 and base.close < base.open and impulse.close > base.high \
            and impulse.close - base.high >= atr * 0.45:
        return Zone(base.low, base.high, 1, ORDER_BLOCK)
    if direction < 0 and base.close > base.open and impulse.close < base.low \
            and base.low - impulse.close >= atr * 0.45:
        return Zone(base.low, base.high, -1, ORDER_BLOCK)
    return None


def detect_sweep(current: Bar, previous: list[Bar], direction: int):
    if not previous:
        return None
    if direction > 0:
        swing = min(bar.low for bar in previous)
        if current.low < swing < current.close:
            return Zone(current.low, swing, 1, SWEEP)
    else:
        swing = max(bar.high for bar in previous)
        if current.high > swing > current.close:
            return Zone(swing, current.high, -1, SWEEP)
    return None


def add_premium_discount(zone: Zone, range_mid: float) -> Zone:
    center = (zone.low + zone.high) / 2
    is_discount = center < range_mid if zone.direction > 0 else center > range_mid
    return Zone(zone.low, zone.high, zone.direction,
                zone.features | (DISCOUNT if is_discount else 0))


def strength(zone: Zone) -> float:
    return ((35 if zone.features & ORDER_BLOCK else 0)
            + (25 if zone.features & FVG else 0)
            + (25 if zone.features & SWEEP else 0)
            + (15 if zone.features & DISCOUNT else 0))


def grade(zone: Zone) -> str:
    value = strength(zone)
    return "A" if value >= 80 else "B" if value >= 60 else "C" if value >= 40 else "D"


def explainable_score(zone: Zone, aligned_bias: bool, m5_confirmed: bool) -> float:
    return min(100, (20 if aligned_bias else 0) + strength(zone) * 0.25
               + (15 if zone.features & FVG else 0)
               + (15 if zone.features & SWEEP else 0)
               + (10 if zone.features & DISCOUNT else 0)
               + (15 if m5_confirmed else 0))


def rr_ratio(entry: float, stop: float, target: float) -> float:
    risk = abs(entry - stop)
    reward = abs(target - entry)
    return reward / risk if risk > 0 and reward > 0 else 0.0


def rr_passes(entry: float, stop: float, target: float, minimum_rr: float) -> bool:
    return rr_ratio(entry, stop, target) >= minimum_rr


def aligned_bias(h4_direction: int, h1_direction: int) -> int:
    return h4_direction if h4_direction != 0 and h4_direction == h1_direction else 0


def structural_target(direction: int, entry: float, opposing_zones: list[Zone],
                       h4_bars: list[Bar]):
    candidates = []
    for zone in opposing_zones:
        if direction > 0 and zone.direction < 0 and zone.low > entry:
            candidates.append(zone.low)
        if direction < 0 and zone.direction > 0 and zone.high < entry:
            candidates.append(zone.high)
    if candidates:
        return min(candidates, key=lambda value: abs(value - entry))
    extremes = []
    for bar in h4_bars:
        if direction > 0 and bar.high > entry:
            extremes.append(bar.high)
        if direction < 0 and bar.low < entry:
            extremes.append(bar.low)
    return (min(extremes, key=lambda value: abs(value - entry)) if extremes else None)


def no_zone_reason(zone_count: int, ob_count: int, fvg_count: int, sweep_count: int) -> str:
    if zone_count:
        return "Zones available"
    return ("No zones: no qualifying OB displacement, ATR-sized FVG, or reclaimed "
            f"liquidity sweep (OB={ob_count} FVG={fvg_count} sweeps={sweep_count})")
