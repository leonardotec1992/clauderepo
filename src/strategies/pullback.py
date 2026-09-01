"""
Strategy 4: PULLBACK to EMA

Rules:
- EMA Fast = 50, EMA Slow = 200.
- BUY signal if:
  - EMA50 > EMA200 (uptrend)
  - Candle Low <= EMA50 (touched/dipped below EMA50)
  - Candle Close > EMA50 (closed back above EMA50)
- SELL signal if:
  - EMA50 < EMA200 (downtrend)
  - Candle High >= EMA50 (touched/exceeded EMA50)
  - Candle Close < EMA50 (closed back below EMA50)
"""

import pandas as pd


def generate_pullback_signals(df: pd.DataFrame) -> pd.Series:
    """
    Generates signals for Strategy 4: PULLBACK to EMA.
    Returns a Series with values: 1 (BUY), -1 (SELL), 0 (HOLD/NO SIGNAL).
    """
    signals = pd.Series(0, index=df.index, dtype=int)

    buy_cond = (df["ema50"] > df["ema200"]) & (df["low"] <= df["ema50"]) & (df["close"] > df["ema50"])
    sell_cond = (df["ema50"] < df["ema200"]) & (df["high"] >= df["ema50"]) & (df["close"] < df["ema50"])

    signals[buy_cond] = 1
    signals[sell_cond] = -1

    return signals
