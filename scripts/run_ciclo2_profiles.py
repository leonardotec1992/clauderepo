import os
import sys

# Ensure project root is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

from src.backtester import calculate_indicators, Backtester, calculate_metrics

def main():
    parquet_path = "data/XAUUSD_M5_2019_2024.parquet"
    if not os.path.exists(parquet_path):
        raise FileNotFoundError(f"Data file not found at {parquet_path}. Run scripts/download_data.py first.")

    print("Loading dataset...")
    df_m5 = pd.read_parquet(parquet_path)
    print(f"Loaded {len(df_m5)} M5 bars from {df_m5.index[0]} to {df_m5.index[-1]}")

    print("Calculating technical indicators...")
    df = calculate_indicators(df_m5)
    print("Indicators calculated.")

    # Chronological 70% In-Sample / 30% Out-Of-Sample split
    total_bars = len(df)
    is_split_idx = int(total_bars * 0.70)

    df_is = df.iloc[:is_split_idx]
    df_oos = df.iloc[is_split_idx:]

    print(f"IS Range : {df_is.index[0]} to {df_is.index[-1]} ({len(df_is)} bars)")
    print(f"OOS Range: {df_oos.index[0]} to {df_oos.index[-1]} ({len(df_oos)} bars)")

    profiles = [
        (0, "MANUAL"),
        (1, "CONSERVADOR"),
        (2, "BALANCEADO"),
        (3, "AGRESIVO")
    ]

    out_dir = "backtests/ciclo2_profiles"
    os.makedirs(out_dir, exist_ok=True)

    results = {}

    for p_id, p_name in profiles:
        print(f"\n==================================================")
        print(f" Running Profile: {p_name} (ID: {p_id})")
        print(f"==================================================")

        # In-Sample Backtest
        print(f"[{p_name}] Running In-Sample (70%)...")
        bt_is = Backtester(df_is, initial_balance=10000.0, params={'Perfil_Riesgo': p_id})
        bt_is.run()

        eq_is_df = pd.DataFrame(bt_is.equity_curve)
        trades_is_df = pd.DataFrame(bt_is.closed_trades)
        metrics_is = calculate_metrics(bt_is.closed_trades, eq_is_df, 10000.0)

        # Out-Of-Sample Backtest
        print(f"[{p_name}] Running Out-Of-Sample (30%)...")
        bt_oos = Backtester(df_oos, initial_balance=10000.0, params={'Perfil_Riesgo': p_id})
        bt_oos.run()

        eq_oos_df = pd.DataFrame(bt_oos.equity_curve)
        trades_oos_df = pd.DataFrame(bt_oos.closed_trades)
        metrics_oos = calculate_metrics(bt_oos.closed_trades, eq_oos_df, 10000.0)

        results[p_name] = {
            'IS': metrics_is,
            'OOS': metrics_oos,
            'eq_is': eq_is_df,
            'eq_oos': eq_oos_df,
            'trades_is': trades_is_df,
            'trades_oos': trades_oos_df
        }

        # Save equity curves CSV
        prefix = f"{p_id}_{p_name.lower()}"
        if not eq_is_df.empty:
            eq_is_df.to_csv(os.path.join(out_dir, f"equity_is_{prefix}.csv"), index=False)
        if not eq_oos_df.empty:
            eq_oos_df.to_csv(os.path.join(out_dir, f"equity_oos_{prefix}.csv"), index=False)

        # Save closed trades CSV
        if not trades_is_df.empty:
            trades_is_df.to_csv(os.path.join(out_dir, f"trades_is_{prefix}.csv"), index=False)
        if not trades_oos_df.empty:
            trades_oos_df.to_csv(os.path.join(out_dir, f"trades_oos_{prefix}.csv"), index=False)

        # Save individual profile chart
        plt.figure(figsize=(12, 6))
        if not eq_is_df.empty:
            plt.plot(eq_is_df['Date'], eq_is_df['Equity'], label=f"IS Equity (PF: {metrics_is['profit_factor']}, Score: {metrics_is['ontester_score']})", color='blue')
        if not eq_oos_df.empty:
            plt.plot(eq_oos_df['Date'], eq_oos_df['Equity'], label=f"OOS Equity (PF: {metrics_oos['profit_factor']}, Score: {metrics_oos['ontester_score']})", color='orange')

        plt.title(f"BayesianGold XAUUSD M5 - Perfil {p_name} (70% IS / 30% OOS)")
        plt.xlabel("Fecha")
        plt.ylabel("Equity (USD)")
        plt.grid(True, alpha=0.3)
        plt.legend()
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, f"equity_curve_{prefix}.png"), dpi=150)
        plt.close()

    # Save combined equity curves chart
    plt.figure(figsize=(14, 7))
    colors = {'MANUAL': 'red', 'CONSERVADOR': 'green', 'BALANCEADO': 'blue', 'AGRESIVO': 'purple'}
    for p_id, p_name in profiles:
        eq_is = results[p_name]['eq_is']
        eq_oos = results[p_name]['eq_oos']
        c = colors[p_name]
        if not eq_is.empty:
            plt.plot(eq_is['Date'], eq_is['Equity'], label=f"{p_name} IS", color=c, linestyle='-')
        if not eq_oos.empty:
            plt.plot(eq_oos['Date'], eq_oos['Equity'], label=f"{p_name} OOS", color=c, linestyle='--')

    plt.title("BayesianGold XAUUSD M5 - Comparativa de Equity Curves (4 Perfiles x IS/OOS)")
    plt.xlabel("Fecha")
    plt.ylabel("Equity (USD)")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "equity_curve_all_profiles.png"), dpi=150)
    plt.close()

    print("\nSummary Results:")
    for p_id, p_name in profiles:
        m_is = results[p_name]['IS']
        m_oos = results[p_name]['OOS']
        print(f"Profile: {p_name}")
        print(f"  IS : Trades={m_is['trades']}, Net={m_is['net_profit']} ({m_is['net_profit_pct']}%), PF={m_is['profit_factor']}, WR={m_is['win_rate']}%, MaxDD={m_is['max_dd_pct']}% (${m_is['max_dd_usd']}), Sharpe={m_is['sharpe_ratio']}, Score={m_is['ontester_score']}")
        print(f"  OOS: Trades={m_oos['trades']}, Net={m_oos['net_profit']} ({m_oos['net_profit_pct']}%), PF={m_oos['profit_factor']}, WR={m_oos['win_rate']}%, MaxDD={m_oos['max_dd_pct']}% (${m_oos['max_dd_usd']}), Sharpe={m_oos['sharpe_ratio']}, Score={m_oos['ontester_score']}")

if __name__ == "__main__":
    main()
