"""
Main execution script for XAUUSD Multi-Strategy Backtest.

Evaluates 4 independent strategies on XAUUSD (Gold):
1. TREND (Donchian + EMA)
2. ORB (Opening Range Breakout - tested on 30m, 60m, 90m ranges)
3. MOMENTUM (ADX + DI)
4. PULLBACK to EMA

Applies realistic transaction costs (0.30 spread per entry) and ATR-based SL/TP (SL = 2*ATR, TP = 4*ATR).
"""

import os
import argparse
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

from src.data_loader import get_data
from src.indicators import add_all_indicators
from src.strategies.trend import generate_trend_signals
from src.strategies.orb import generate_orb_signals
from src.strategies.momentum import generate_momentum_signals
from src.strategies.pullback import generate_pullback_signals
from src.backtester import run_strategy_backtest


def run_all_strategies_on_df(df: pd.DataFrame, timeframe_label: str, spread: float = 0.30):
    """
    Runs all 4 strategies (plus ORB variations) on the given DataFrame.
    Returns:
      - metrics_df: Summary DataFrame of performance metrics
      - all_trades_df: Concatenated DataFrame of all trades labeled by strategy
      - equity_dict: Dictionary mapping strategy name to equity curve Series
    """
    df_calc = add_all_indicators(df)

    # Define strategy configurations
    strategy_runs = []

    # 1. TREND
    trend_sig = generate_trend_signals(df_calc)
    strategy_runs.append({
        "name": "TREND (Donchian+EMA)",
        "signals": trend_sig,
        "max_trades_per_day": None
    })

    # 2. ORB (Robustness Test: 30, 60, 90 minutes)
    for r_min in [30, 60, 90]:
        orb_sig = generate_orb_signals(df_calc, open_time_str="08:00", range_minutes=r_min)
        strategy_runs.append({
            "name": f"ORB (Range {r_min}m)",
            "signals": orb_sig,
            "max_trades_per_day": 1
        })

    # 3. MOMENTUM
    mom_sig = generate_momentum_signals(df_calc)
    strategy_runs.append({
        "name": "MOMENTUM (ADX+DI)",
        "signals": mom_sig,
        "max_trades_per_day": None
    })

    # 4. PULLBACK
    pull_sig = generate_pullback_signals(df_calc)
    strategy_runs.append({
        "name": "PULLBACK (EMA)",
        "signals": pull_sig,
        "max_trades_per_day": None
    })

    # Execute backtests
    metrics_list = []
    all_trades_list = []
    equity_dict = {}

    for strat in strategy_runs:
        res = run_strategy_backtest(
            df=df_calc,
            signals=strat["signals"],
            strategy_name=strat["name"],
            spread=spread,
            initial_capital=10000.0,
            max_trades_per_day=strat["max_trades_per_day"]
        )
        metrics_list.append(res["metrics"])

        if not res["trades_df"].empty:
            res["trades_df"]["timeframe"] = timeframe_label
            all_trades_list.append(res["trades_df"])

        equity_dict[strat["name"]] = res["equity_curve"]

    metrics_df = pd.DataFrame(metrics_list)
    all_trades_df = pd.concat(all_trades_list, ignore_index=True) if all_trades_list else pd.DataFrame()

    return metrics_df, all_trades_df, equity_dict, df_calc


def plot_results(equity_dict: dict, df_time: pd.Series, timeframe_label: str, output_dir: str):
    """
    Generates and saves Equity Curve and Drawdown plots for the given timeframe.
    """
    os.makedirs(output_dir, exist_ok=True)

    # 1. Equity Curves Plot
    plt.figure(figsize=(12, 6))
    for name, eq_series in equity_dict.items():
        plt.plot(df_time, eq_series.values, label=name, linewidth=1.5)

    plt.title(f"XAUUSD Equity Curves ({timeframe_label}) - Initial $10,000 (Spread 0.30)", fontsize=14, fontweight="bold")
    plt.xlabel("Date", fontsize=12)
    plt.ylabel("Account Equity ($)", fontsize=12)
    plt.axhline(10000.0, color="gray", linestyle="--", alpha=0.7, label="Initial Capital")
    plt.grid(True, alpha=0.3)
    plt.legend(loc="upper left")
    plt.tight_layout()
    equity_img_path = os.path.join(output_dir, f"equity_curves_{timeframe_label}.png")
    plt.savefig(equity_img_path, dpi=300)
    plt.close()

    # 2. Drawdown Plot
    plt.figure(figsize=(12, 6))
    for name, eq_series in equity_dict.items():
        peak = eq_series.cummax()
        dd_pct = ((eq_series - peak) / peak) * 100.0
        plt.plot(df_time, dd_pct.values, label=name, linewidth=1.5)

    plt.title(f"XAUUSD Drawdown (%) ({timeframe_label})", fontsize=14, fontweight="bold")
    plt.xlabel("Date", fontsize=12)
    plt.ylabel("Drawdown (%)", fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.legend(loc="lower left")
    plt.tight_layout()
    dd_img_path = os.path.join(output_dir, f"drawdown_{timeframe_label}.png")
    plt.savefig(dd_img_path, dpi=300)
    plt.close()

    print(f"Saved charts to {equity_img_path} and {dd_img_path}")


def main():
    parser = argparse.ArgumentParser(description="XAUUSD 4 Trend Strategies Backtester")
    parser.add_argument("--csv", type=str, default=None, help="Path to local MT5 CSV file (optional)")
    parser.add_argument("--spread", type=float, default=0.30, help="Spread cost in price points (default 0.30)")
    args = parser.parse_args()

    output_dir = "resultados"
    os.makedirs(output_dir, exist_ok=True)

    if args.csv and os.path.exists(args.csv):
        print(f"--- Running Backtest on Local CSV: {args.csv} ---")
        df = get_data(source="csv", filepath=args.csv)
        tf_label = "Local_CSV"

        m_df, trades_df, eq_dict, df_calc = run_all_strategies_on_df(df, tf_label, spread=args.spread)
        print("\n=== PERFORMANCE METRICS (Local CSV) ===")
        print(m_df.to_string(index=False))

        # Save files
        m_df.to_csv(os.path.join(output_dir, f"metrics_{tf_label}.csv"), index=False)
        trades_df.to_csv(os.path.join(output_dir, f"trades_{tf_label}.csv"), index=False)
        plot_results(eq_dict, df_calc["time"], tf_label, output_dir)

    else:
        print("--- Running Backtest on yfinance XAUUSD (GC=F) Data ---")
        timeframes = [
            ("M5", "5m", "60d"),
            ("M15", "15m", "60d"),
            ("H1", "1h", "730d")
        ]

        all_summary_metrics = []

        for tf_label, interval, period in timeframes:
            print(f"\n=======================================================")
            print(f"  Fetching & Backtesting Timeframe: {tf_label} (Interval: {interval}, Period: {period})")
            print(f"=======================================================")

            try:
                df = get_data(source="yfinance", symbol="GC=F", interval=interval, period=period)
            except Exception as e:
                print(f"Error fetching data for {tf_label}: {e}")
                continue

            start_date = df["time"].min().strftime("%Y-%m-%d %H:%M")
            end_date = df["time"].max().strftime("%Y-%m-%d %H:%M")
            print(f"Candles count: {len(df)} | Date range: {start_date} to {end_date}")

            m_df, trades_df, eq_dict, df_calc = run_all_strategies_on_df(df, tf_label, spread=args.spread)
            m_df["Timeframe"] = tf_label
            m_df["Date Range"] = f"{start_date} to {end_date}"

            print("\n=== PERFORMANCE METRICS ===")
            print(m_df[["Timeframe", "Strategy", "Trades", "Net Profit ($)", "Win Rate (%)", "Profit Factor", "Sharpe Ratio", "Max Drawdown (%)"]].to_string(index=False))

            # Save per-timeframe results
            m_df.to_csv(os.path.join(output_dir, f"metrics_{tf_label}.csv"), index=False)
            trades_df.to_csv(os.path.join(output_dir, f"trades_{tf_label}.csv"), index=False)
            plot_results(eq_dict, df_calc["time"], tf_label, output_dir)

            all_summary_metrics.append(m_df)

        if all_summary_metrics:
            combined_summary = pd.concat(all_summary_metrics, ignore_index=True)
            combined_summary.to_csv(os.path.join(output_dir, "all_strategies_summary.csv"), index=False)
            print("\nSaved combined metrics summary to resultados/all_strategies_summary.csv")


if __name__ == "__main__":
    main()
