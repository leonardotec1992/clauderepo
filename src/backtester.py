"""
Backtesting engine and performance metrics module for XAUUSD trading strategies.
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Any


def run_strategy_backtest(
    df: pd.DataFrame,
    signals: pd.Series,
    strategy_name: str,
    spread: float = 0.30,
    initial_capital: float = 10000.0,
    max_trades_per_day: int = None
) -> Dict[str, Any]:
    """
    Backtests a single strategy on OHLCV data.

    Args:
        df: DataFrame with OHLCV and atr14 indicator.
        signals: Series with 1 (BUY), -1 (SELL), 0 (HOLD).
        strategy_name: Name label for the strategy.
        spread: Transaction cost spread in price points (default 0.30 = $0.30/oz).
        initial_capital: Starting equity for equity curve tracking.
        max_trades_per_day: Max trades allowed per day (e.g. 1 for ORB).

    Returns:
        Dict containing metrics, trades list, equity curve Series, and daily returns.
    """
    trades: List[Dict[str, Any]] = []
    equity_curve = pd.Series(index=df.index, dtype=float)
    equity_curve.iloc[0] = initial_capital

    current_equity = initial_capital
    position = None  # None or dict holding open position details
    daily_trade_count: Dict[Any, int] = {}

    for i in range(len(df)):
        candle = df.iloc[i]
        curr_time = candle["time"]
        curr_date = curr_time.date()
        open_p = candle["open"]
        high_p = candle["high"]
        low_p = candle["low"]
        close_p = candle["close"]
        atr_v = candle["atr14"] if "atr14" in candle and not np.isnan(candle["atr14"]) else 5.0

        # Check existing position exit conditions (SL / TP)
        if position is not None:
            pos_type = position["type"]
            sl_price = position["sl"]
            tp_price = position["tp"]
            entry_price = position["entry_price"]

            exit_price = None
            exit_reason = None

            if pos_type == "BUY":
                # Check if SL or TP hit
                sl_hit = low_p <= sl_price
                tp_hit = high_p >= tp_price

                if sl_hit and tp_hit:
                    # Pessimistic assumption: SL hit first
                    exit_price = sl_price
                    exit_reason = "SL"
                elif sl_hit:
                    exit_price = sl_price
                    exit_reason = "SL"
                elif tp_hit:
                    exit_price = tp_price
                    exit_reason = "TP"

                if exit_price is not None:
                    pnl = exit_price - entry_price
                    current_equity += pnl
                    trades.append({
                        "strategy": strategy_name,
                        "type": pos_type,
                        "entry_time": position["entry_time"],
                        "entry_price": entry_price,
                        "exit_time": curr_time,
                        "exit_price": exit_price,
                        "sl": sl_price,
                        "tp": tp_price,
                        "pnl": pnl,
                        "return_pct": (pnl / initial_capital) * 100,
                        "exit_reason": exit_reason
                    })
                    position = None

            elif pos_type == "SELL":
                sl_hit = high_p >= sl_price
                tp_hit = low_p <= tp_price

                if sl_hit and tp_hit:
                    # Pessimistic assumption: SL hit first
                    exit_price = sl_price
                    exit_reason = "SL"
                elif sl_hit:
                    exit_price = sl_price
                    exit_reason = "SL"
                elif tp_hit:
                    exit_price = tp_price
                    exit_reason = "TP"

                if exit_price is not None:
                    pnl = entry_price - exit_price
                    current_equity += pnl
                    trades.append({
                        "strategy": strategy_name,
                        "type": pos_type,
                        "entry_time": position["entry_time"],
                        "entry_price": entry_price,
                        "exit_time": curr_time,
                        "exit_price": exit_price,
                        "sl": sl_price,
                        "tp": tp_price,
                        "pnl": pnl,
                        "return_pct": (pnl / initial_capital) * 100,
                        "exit_reason": exit_reason
                    })
                    position = None

        # Check for new entry signal if no position is open
        if position is None and i < len(df) - 1:
            sig = signals.iloc[i]
            if sig != 0:
                # Check max trades per day rule if applicable
                trades_today = daily_trade_count.get(curr_date, 0)
                if max_trades_per_day is None or trades_today < max_trades_per_day:
                    sl_dist = 2.0 * atr_v
                    tp_dist = 2.0 * sl_dist  # 4.0 * atr

                    if sig == 1:  # BUY
                        # Entry cost: pay spread at entry
                        real_entry = close_p + spread
                        sl_price = close_p - sl_dist
                        tp_price = close_p + tp_dist

                        position = {
                            "type": "BUY",
                            "entry_time": curr_time,
                            "entry_price": real_entry,
                            "sl": sl_price,
                            "tp": tp_price
                        }
                        daily_trade_count[curr_date] = trades_today + 1

                    elif sig == -1:  # SELL
                        real_entry = close_p - spread
                        sl_price = close_p + sl_dist
                        tp_price = close_p - tp_dist

                        position = {
                            "type": "SELL",
                            "entry_time": curr_time,
                            "entry_price": real_entry,
                            "sl": sl_price,
                            "tp": tp_price
                        }
                        daily_trade_count[curr_date] = trades_today + 1

        equity_curve.iloc[i] = current_equity

    # Close any open position at the end of the data stream
    if position is not None:
        last_candle = df.iloc[-1]
        exit_price = last_candle["close"]
        if position["type"] == "BUY":
            pnl = exit_price - position["entry_price"]
        else:
            pnl = position["entry_price"] - exit_price

        current_equity += pnl
        equity_curve.iloc[-1] = current_equity
        trades.append({
            "strategy": strategy_name,
            "type": position["type"],
            "entry_time": position["entry_time"],
            "entry_price": position["entry_price"],
            "exit_time": last_candle["time"],
            "exit_price": exit_price,
            "sl": position["sl"],
            "tp": position["tp"],
            "pnl": pnl,
            "return_pct": (pnl / initial_capital) * 100,
            "exit_reason": "END"
        })

    # Metrics calculation
    trades_df = pd.DataFrame(trades)
    metrics = calculate_metrics(trades_df, equity_curve, initial_capital, strategy_name)

    return {
        "strategy": strategy_name,
        "metrics": metrics,
        "trades_df": trades_df,
        "equity_curve": equity_curve
    }


def calculate_metrics(trades_df: pd.DataFrame, equity_curve: pd.Series, initial_capital: float, strategy_name: str) -> Dict[str, Any]:
    """
    Computes summary metrics: trade count, net profit, winrate, profit factor,
    Sharpe ratio, max drawdown, average win/loss.
    """
    if trades_df.empty:
        return {
            "Strategy": strategy_name,
            "Trades": 0,
            "Net Profit ($)": 0.0,
            "Win Rate (%)": 0.0,
            "Profit Factor": 0.0,
            "Sharpe Ratio": 0.0,
            "Max Drawdown ($)": 0.0,
            "Max Drawdown (%)": 0.0,
            "Avg Win ($)": 0.0,
            "Avg Loss ($)": 0.0,
            "Win/Loss Ratio": 0.0
        }

    n_trades = len(trades_df)
    net_profit = trades_df["pnl"].sum()

    wins = trades_df[trades_df["pnl"] > 0]["pnl"]
    losses = trades_df[trades_df["pnl"] < 0]["pnl"]

    n_wins = len(wins)
    win_rate = (n_wins / n_trades) * 100.0 if n_trades > 0 else 0.0

    gross_profit = wins.sum() if len(wins) > 0 else 0.0
    gross_loss = abs(losses.sum()) if len(losses) > 0 else 0.0

    if gross_loss == 0.0:
        profit_factor = float("inf") if gross_profit > 0 else 0.0
    else:
        profit_factor = gross_profit / gross_loss

    avg_win = wins.mean() if len(wins) > 0 else 0.0
    avg_loss = losses.mean() if len(losses) > 0 else 0.0  # negative number
    win_loss_ratio = abs(avg_win / avg_loss) if avg_loss != 0 else 0.0

    # Drawdown calculation
    peak = equity_curve.cummax()
    drawdown = equity_curve - peak
    drawdown_pct = (drawdown / peak) * 100.0

    max_dd_usd = abs(drawdown.min())
    max_dd_pct = abs(drawdown_pct.min())

    # Daily returns Sharpe Ratio
    daily_equity = equity_curve.groupby(equity_curve.index).last()
    daily_returns = daily_equity.pct_change().dropna()

    if len(daily_returns) > 1 and daily_returns.std() > 0:
        sharpe_ratio = (daily_returns.mean() / daily_returns.std()) * np.sqrt(252)
    else:
        sharpe_ratio = 0.0

    return {
        "Strategy": strategy_name,
        "Trades": n_trades,
        "Net Profit ($)": round(net_profit, 2),
        "Win Rate (%)": round(win_rate, 2),
        "Profit Factor": round(profit_factor, 2) if profit_factor != float("inf") else 999.0,
        "Sharpe Ratio": round(sharpe_ratio, 2),
        "Max Drawdown ($)": round(max_dd_usd, 2),
        "Max Drawdown (%)": round(max_dd_pct, 2),
        "Avg Win ($)": round(avg_win, 2),
        "Avg Loss ($)": round(avg_loss, 2),
        "Win/Loss Ratio": round(win_loss_ratio, 2)
    }
