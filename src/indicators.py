"""
Technical indicators used across strategies:
- EMA (Exponential Moving Average)
- Donchian Channels
- ADX and +DI/-DI (Directional Movement)
- ATR (Average True Range)
"""

import pandas as pd
import numpy as np


def compute_ema(series: pd.Series, period: int) -> pd.Series:
    """Calculates Exponential Moving Average."""
    return series.ewm(span=period, adjust=False).mean()


def compute_atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Calculates Average True Range (ATR)."""
    high = df["high"]
    low = df["low"]
    close = df["close"].shift(1)

    tr1 = high - low
    tr2 = (high - close).abs()
    tr3 = (low - close).abs()

    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr = tr.ewm(span=period, adjust=False).mean()
    return atr


def compute_donchian(df: pd.DataFrame, period: int = 20) -> tuple[pd.Series, pd.Series]:
    """
    Calculates Donchian Channel (High Max, Low Min) over the previous N candles (shifted by 1).
    Excludes the current candle.
    """
    donchian_high = df["high"].shift(1).rolling(window=period).max()
    donchian_low = df["low"].shift(1).rolling(window=period).min()
    return donchian_high, donchian_low


def compute_adx_di(df: pd.DataFrame, period: int = 14) -> tuple[pd.Series, pd.Series, pd.Series]:
    """
    Calculates ADX, +DI, and -DI using Wilder's Smoothing.
    """
    high = df["high"]
    low = df["low"]
    close = df["close"]

    up_move = high.diff()
    down_move = -low.diff()

    plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
    minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)

    # True Range
    prev_close = close.shift(1)
    tr1 = high - low
    tr2 = (high - prev_close).abs()
    tr3 = (low - prev_close).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

    # Wilder's smoothing function (alpha = 1 / period)
    def wilder_smooth(series: pd.Series, period: int) -> pd.Series:
        smoothed = pd.Series(index=series.index, dtype=float)
        if len(series) < period:
            return smoothed
        smoothed.iloc[period - 1] = series.iloc[:period].sum()
        for i in range(period, len(series)):
            smoothed.iloc[i] = smoothed.iloc[i - 1] - (smoothed.iloc[i - 1] / period) + series.iloc[i]
        return smoothed

    tr_smoothed = wilder_smooth(tr, period)
    plus_dm_smoothed = wilder_smooth(pd.Series(plus_dm, index=df.index), period)
    minus_dm_smoothed = wilder_smooth(pd.Series(minus_dm, index=df.index), period)

    plus_di = 100 * (plus_dm_smoothed / tr_smoothed)
    minus_di = 100 * (minus_dm_smoothed / tr_smoothed)

    di_diff = (plus_di - minus_di).abs()
    di_sum = plus_di + minus_di
    dx = 100 * (di_diff / di_sum.replace(0, np.nan))

    adx = wilder_smooth(dx.fillna(0), period)
    # Re-normalize ADX for Wilder's (divide first sum by period for average)
    adx_final = pd.Series(index=df.index, dtype=float)
    if len(dx) >= 2 * period - 1:
        # standard ADX is smoothed DX
        adx_final = dx.ewm(alpha=1/period, adjust=False).mean()
    else:
        adx_final = dx.ewm(span=period, adjust=False).mean()

    return adx_final, plus_di, minus_di


def add_all_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Applies all indicator calculations to the DataFrame."""
    df = df.copy()
    df["ema50"] = compute_ema(df["close"], 50)
    df["ema200"] = compute_ema(df["close"], 200)
    df["atr14"] = compute_atr(df, 14)
    df["donchian_high_20"], df["donchian_low_20"] = compute_donchian(df, 20)
    df["adx14"], df["plus_di14"], df["minus_di14"] = compute_adx_di(df, 14)
    return df
