"""
Strategy 1: TREND (Donchian + EMA)

Rules:
- Donchian = Max/Min of previous 20 candles (excluding current candle).
- EMA Fast = 50, EMA Slow = 200.
- BUY signal if close > donchian_high(20) AND ema50 > ema200.
- SELL signal if close < donchian_low(20) AND ema50 < ema200.
"""

import pandas as pd


def generate_trend_signals(df: pd.DataFrame) -> pd.Series:
    """
    Generates signals for Strategy 1: TREND (Donchian + EMA).
    Returns a Series with values: 1 (BUY), -1 (SELL), 0 (HOLD/NO SIGNAL).
    """
    signals = pd.Series(0, index=df.index, dtype=int)

    buy_cond = (df["close"] > df["donchian_high_20"]) & (df["ema50"] > df["ema200"])
    sell_cond = (df["close"] < df["donchian_low_20"]) & (df["ema50"] < df["ema200"])

    signals[buy_cond] = 1
    signals[sell_cond] = -1

    return signals
