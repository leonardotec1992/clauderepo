"""
Strategy 3: MOMENTUM (ADX + DI)

Rules:
- ADX period 14, filter: ADX > 25.
- BUY signal if ADX > 25 AND +DI > -DI AND current candle is bullish (close > open).
- SELL signal if ADX > 25 AND -DI > +DI AND current candle is bearish (close < open).
"""

import pandas as pd


def generate_momentum_signals(df: pd.DataFrame) -> pd.Series:
    """
    Generates signals for Strategy 3: MOMENTUM (ADX + DI).
    Returns a Series with values: 1 (BUY), -1 (SELL), 0 (HOLD/NO SIGNAL).
    """
    signals = pd.Series(0, index=df.index, dtype=int)

    is_bullish = df["close"] > df["open"]
    is_bearish = df["close"] < df["open"]

    buy_cond = (df["adx14"] > 25) & (df["plus_di14"] > df["minus_di14"]) & is_bullish
    sell_cond = (df["adx14"] > 25) & (df["minus_di14"] > df["plus_di14"]) & is_bearish

    signals[buy_cond] = 1
    signals[sell_cond] = -1

    return signals
