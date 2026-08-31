"""
Strategy 2: ORB (Opening Range Breakout)

Rules:
- Configurable opening time (default "08:00" UTC/local).
- Range = Max High and Min Low of candles during the first range_minutes (30, 60, or 90 min).
- After range closes:
  - BUY signal if close > range_high.
  - SELL signal if close < range_low.
- Constraint: Maximum 1 trade per day for ORB.
"""

import pandas as pd
import datetime


def generate_orb_signals(df: pd.DataFrame, open_time_str: str = "08:00", range_minutes: int = 60) -> pd.DataFrame:
    """
    Computes daily ORB levels (range_high, range_low, range_complete) for each candle.
    Returns df copy with columns:
    - orb_high: High of opening range for that day
    - orb_low: Low of opening range for that day
    - orb_active: True if current candle is after the opening range window for that day
    - signal: 1 (BUY breakout), -1 (SELL breakout), 0 (None)
    """
    df_res = df.copy()
    df_res["orb_high"] = float("nan")
    df_res["orb_low"] = float("nan")
    df_res["orb_active"] = False
    df_res["orb_signal"] = 0

    open_h, open_m = map(int, open_time_str.split(":"))
    open_time_obj = datetime.time(open_h, open_m)

    # Calculate range end time
    dummy_dt = datetime.datetime(2000, 1, 1, open_h, open_m)
    range_end_dt = dummy_dt + datetime.timedelta(minutes=range_minutes)
    range_end_time_obj = range_end_dt.time()

    # Group by date
    df_res["_date"] = df_res["time"].dt.date

    for date_val, group in df_res.groupby("_date"):
        # Identify candles within the range [open_time, range_end_time)
        times = group["time"].dt.time

        # Range candles
        if range_end_dt.day == 1: # Same day range
            range_mask = (times >= open_time_obj) & (times < range_end_time_obj)
            after_mask = (times >= range_end_time_obj)
        else: # Crosses midnight (rare for 30-90m starting at 08:00)
            range_mask = (times >= open_time_obj) | (times < range_end_time_obj)
            after_mask = (times >= range_end_time_obj) & (times < open_time_obj)

        range_candles = group[range_mask]

        if not range_candles.empty:
            r_high = range_candles["high"].max()
            r_low = range_candles["low"].min()

            df_res.loc[group.index, "orb_high"] = r_high
            df_res.loc[group.index, "orb_low"] = r_low
            df_res.loc[group[after_mask].index, "orb_active"] = True

    # Signal logic
    active_mask = df_res["orb_active"]
    buy_cond = active_mask & (df_res["close"] > df_res["orb_high"])
    sell_cond = active_mask & (df_res["close"] < df_res["orb_low"])

    df_res.loc[buy_cond, "orb_signal"] = 1
    df_res.loc[sell_cond, "orb_signal"] = -1

    df_res.drop(columns=["_date"], inplace=True)
    return df_res["orb_signal"]
