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

    # Run Baseline Backtest - In Sample
    print("\nRunning Baseline Backtest (In-Sample 70%)...")
    bt_is = Backtester(df_is, initial_balance=10000.0)
    bt_is.run()

    eq_is_df = pd.DataFrame(bt_is.equity_curve)
    metrics_is = calculate_metrics(bt_is.closed_trades, eq_is_df, 10000.0)
    print("IS Metrics:", metrics_is)

    # Run Baseline Backtest - Out Of Sample
    print("\nRunning Baseline Backtest (Out-Of-Sample 30%)...")
    bt_oos = Backtester(df_oos, initial_balance=10000.0)
    bt_oos.run()

    eq_oos_df = pd.DataFrame(bt_oos.equity_curve)
    metrics_oos = calculate_metrics(bt_oos.closed_trades, eq_oos_df, 10000.0)
    print("OOS Metrics:", metrics_oos)

    # Output directory
    out_dir = "backtests/ciclo1_baseline"
    os.makedirs(out_dir, exist_ok=True)

    # Plot Equity Curves
    plt.figure(figsize=(12, 6))
    if not eq_is_df.empty:
        plt.plot(eq_is_df['Date'], eq_is_df['Equity'], label=f"IS Equity (PF: {metrics_is['profit_factor']}, Score: {metrics_is['ontester_score']})", color='blue')
    if not eq_oos_df.empty:
        plt.plot(eq_oos_df['Date'], eq_oos_df['Equity'], label=f"OOS Equity (PF: {metrics_oos['profit_factor']}, Score: {metrics_oos['ontester_score']})", color='orange')

    plt.title("BayesianGold XAUUSD M5 - Baseline Ciclo 1 Equity Curve (70% IS / 30% OOS)")
    plt.xlabel("Fecha")
    plt.ylabel("Equity (USD)")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()

    fig_path = os.path.join(out_dir, "equity_curve.png")
    plt.savefig(fig_path, dpi=150)
    plt.close()
    print(f"Equity curve chart saved to {fig_path}")

    # Generate README.md for Ciclo 1 Baseline
    readme_content = f"""# Ciclo 1: Baseline (Parámetros por defecto de fábrica)

## Descripción y Configuración
- **Símbolo**: XAUUSD
- **Timeframe**: M5
- **Período Total**: 2019-01-01 a 2024-12-31 (~5 años)
- **Fuente de Datos**: HuggingFace (`ZombitX64/xauusd-gold-price-historical-data-2004-2025`)
- **Supuestos de Mercado**:
  - Spread: 30 puntos ($0.30 / oz de oro)
  - Comisión: $3.50 USD por lote completo (round turn)
- **División de Datos**:
  - In-Sample (IS - 70%): {df_is.index[0].strftime('%Y-%m-%d')} a {df_is.index[-1].strftime('%Y-%m-%d')} ({len(df_is)} velas M5)
  - Out-Of-Sample (OOS - 30%): {df_oos.index[0].strftime('%Y-%m-%d')} a {df_oos.index[-1].strftime('%Y-%m-%d')} ({len(df_oos)} velas M5)

## Resultados Métricas Baseline

| Métrica | In-Sample (IS 70%) | Out-Of-Sample (OOS 30%) |
| :--- | :---: | :---: |
| **Operaciones** | {metrics_is['trades']} | {metrics_oos['trades']} |
| **Ganancia Neta ($)** | ${metrics_is['net_profit']} | ${metrics_oos['net_profit']} |
| **Profit Factor (PF)** | {metrics_is['profit_factor']} | {metrics_oos['profit_factor']} |
| **Win Rate (%)** | {metrics_is['win_rate']}% | {metrics_oos['win_rate']}% |
| **Max Drawdown (%)** | {metrics_is['max_dd_pct']}% | {metrics_oos['max_dd_pct']}% |
| **Sharpe Ratio** | {metrics_is['sharpe_ratio']} | {metrics_oos['sharpe_ratio']} |
| **Score OnTester** | {metrics_is['ontester_score']} | {metrics_oos['ontester_score']} |

## Instrucciones para ejecutar
Para reproducir la prueba baseline:
```bash
python3 scripts/run_ciclo1.py
```
"""
    readme_path = os.path.join(out_dir, "README.md")
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(readme_content)

    print(f"README saved to {readme_path}")

if __name__ == "__main__":
    main()
