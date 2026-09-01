"""
Data loader module for XAUUSD (Gold) candles from yfinance or local CSV files.
"""

import os
import pandas as pd
import yfinance as yf


def download_yfinance_data(symbol: str = "GC=F", interval: str = "5m", period: str = "60d") -> pd.DataFrame:
    """
    Downloads OHLCV candle data from yfinance.

    Args:
        symbol: Ticker symbol (default 'GC=F' for Gold Futures, or 'XAUUSD=X')
        interval: Data granularity ('5m', '15m', '1h')
        period: Time span (e.g., '60d', '60d', '730d')

    Returns:
        pd.DataFrame with columns: time, open, high, low, close, volume
    """
    df = yf.download(symbol, period=period, interval=interval, progress=False)
    if df.empty:
        raise ValueError(f"No data returned from yfinance for symbol {symbol}, interval {interval}")

    # Handle MultiIndex columns if present (yfinance 0.2.x+ format)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0].lower() for col in df.columns]
    else:
        df.columns = [col.lower() for col in df.columns]

    df = df.reset_index()

    # Find timestamp column (Datetime or Date)
    time_col = None
    for col in df.columns:
        if col.lower() in ["datetime", "date", "time"]:
            time_col = col
            break

    if time_col is None:
        time_col = df.columns[0]

    df.rename(columns={time_col: "time"}, inplace=True)
    df["time"] = pd.to_datetime(df["time"])

    # Ensure required columns exist
    for c in ["open", "high", "low", "close"]:
        if c not in df.columns:
            raise KeyError(f"Missing required price column: {c}")

    if "volume" not in df.columns:
        df["volume"] = 0.0

    df = df[["time", "open", "high", "low", "close", "volume"]].copy()
    df.sort_values("time", inplace=True)
    df.reset_index(drop=True, inplace=True)

    # Convert numeric columns to float
    for c in ["open", "high", "low", "close", "volume"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    df.dropna(subset=["open", "high", "low", "close"], inplace=True)
    return df


def load_local_csv(filepath: str) -> pd.DataFrame:
    """
    Loads OHLCV candles from a local CSV file (e.g. exported from MT5).
    Supports flexible column names:
    - time/datetime/date/<date>/<time>
    - open, high, low, close, volume/vol/tickvol

    Args:
        filepath: Path to the CSV file.

    Returns:
        pd.DataFrame with standard columns: time, open, high, low, close, volume
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Local CSV file not found: {filepath}")

    # Try reading with common separators
    try:
        df = pd.read_csv(filepath, sep=None, engine="python")
    except Exception:
        df = pd.read_csv(filepath)

    df.columns = [str(c).strip().lower() for c in df.columns]

    # Handle MT5 format where Date and Time are in separate columns (<DATE> and <TIME>)
    if "date" in df.columns and "time" in df.columns:
        df["time"] = pd.to_datetime(df["date"].astype(str) + " " + df["time"].astype(str))
    elif "<date>" in df.columns and "<time>" in df.columns:
        df["time"] = pd.to_datetime(df["<date>"].astype(str) + " " + df["<time>"].astype(str))
    else:
        # Look for time or datetime
        time_col = None
        for col in df.columns:
            if "time" in col or "date" in col:
                time_col = col
                break
        if time_col:
            df.rename(columns={time_col: "time"}, inplace=True)
            df["time"] = pd.to_datetime(df["time"])
        else:
            raise KeyError("Could not identify time/date column in CSV.")

    # Standardize OHLCV column names
    rename_dict = {}
    for col in df.columns:
        c_clean = col.replace("<", "").replace(">", "").lower()
        if c_clean in ["open", "high", "low", "close", "volume"]:
            rename_dict[col] = c_clean
        elif c_clean in ["vol", "tickvol", "vol<tickvol>"]:
            rename_dict[col] = "volume"

    df.rename(columns=rename_dict, inplace=True)

    for req in ["open", "high", "low", "close"]:
        if req not in df.columns:
            raise KeyError(f"CSV missing required OHLC column: '{req}'")

    if "volume" not in df.columns:
        df["volume"] = 0.0

    df = df[["time", "open", "high", "low", "close", "volume"]].copy()
    df.sort_values("time", inplace=True)
    df.reset_index(drop=True, inplace=True)

    for c in ["open", "high", "low", "close", "volume"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    df.dropna(subset=["open", "high", "low", "close"], inplace=True)
    return df


def get_data(source: str = "yfinance", filepath: str = None, symbol: str = "GC=F", interval: str = "5m", period: str = "60d") -> pd.DataFrame:
    """
    Unified interface to get candle data from yfinance or a local CSV.
    """
    if source.lower() == "csv":
        if not filepath:
            raise ValueError("Filepath must be provided for CSV source.")
        return load_local_csv(filepath)
    else:
        return download_yfinance_data(symbol=symbol, interval=interval, period=period)
