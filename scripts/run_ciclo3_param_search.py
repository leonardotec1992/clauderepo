import os
import sys
import time
import multiprocessing as mp
import numpy as np
import pandas as pd

# Ensure project root is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.backtester import calculate_indicators, Backtester, calculate_metrics

def generate_param_combinations(n_samples=500, seed=42):
    np.random.seed(seed)
    combinations = []
    for i in range(n_samples):
        combo = {
            'param_id': i + 1,
            'InpThreshold': round(float(np.random.uniform(0.50, 0.80)), 4),
            'InpW_RSI': round(float(np.random.uniform(0.0, 2.0)), 4),
            'InpW_CCI': round(float(np.random.uniform(0.0, 2.0)), 4),
            'InpW_Slope': round(float(np.random.uniform(0.0, 2.0)), 4),
            'InpW_Return': round(float(np.random.uniform(0.0, 2.0)), 4),
            'InpW_Trend': round(float(np.random.uniform(0.0, 2.0)), 4),
            'InpSL_ATR': round(float(np.random.uniform(1.0, 4.0)), 4),
            'InpTP_R': round(float(np.random.uniform(0.5, 3.0)), 4),
        }
        combinations.append(combo)
    return combinations

def _run_single_backtest(args):
    combo, df_subset, profile_id, flat_sizing = args

    params = {
        'InpThreshold': combo['InpThreshold'],
        'InpW_RSI': combo['InpW_RSI'],
        'InpW_CCI': combo['InpW_CCI'],
        'InpW_Slope': combo['InpW_Slope'],
        'InpW_Return': combo['InpW_Return'],
        'InpW_Trend': combo['InpW_Trend'],
        'InpSL_ATR': combo['InpSL_ATR'],
        'InpTP_R': combo['InpTP_R'],
        'Perfil_Riesgo': profile_id
    }

    if flat_sizing:
        # Etapa A overrides: flat 0.03 lot, no compounding, no layering
        params.update({
            'StartingLots': 0.03,
            'AutoCompound': False,
            'Usar_Compuesto': False,
            'InpUseLayers': False,
            'Perfil_Riesgo': 0 # MANUAL profile for flat sizing
        })

    bt = Backtester(df_subset, initial_balance=10000.0, params=params)
    bt.run()

    eq_df = pd.DataFrame(bt.equity_curve)
    metrics = calculate_metrics(bt.closed_trades, eq_df, 10000.0)

    res = dict(combo)
    res.update(metrics)
    return res

def run_batch_backtests(combinations, df_subset, profile_id=0, flat_sizing=True, n_workers=None):
    if n_workers is None:
        n_workers = min(mp.cpu_count(), 4)

    tasks = [(combo, df_subset, profile_id, flat_sizing) for combo in combinations]

    with mp.Pool(processes=n_workers) as pool:
        results = pool.map(_run_single_backtest, tasks)

    return results

def main():
    parquet_path = "data/XAUUSD_M5_2019_2024.parquet"
    if not os.path.exists(parquet_path):
        raise FileNotFoundError(f"Data file not found at {parquet_path}. Run scripts/download_data.py first.")

    out_dir = "backtests/ciclo3_param_search"
    os.makedirs(out_dir, exist_ok=True)

    print("=== Ciclo 3: Búsqueda Amplia de Parámetros ===")
    print("Cargando dataset y precalculando indicadores...")
    df_m5 = pd.read_parquet(parquet_path)
    df = calculate_indicators(df_m5)

    total_bars = len(df)
    is_split_idx = int(total_bars * 0.70)
    df_is = df.iloc[:is_split_idx]
    df_oos = df.iloc[is_split_idx:]

    print(f"Total barras: {total_bars}")
    print(f"IS  Range: {df_is.index[0]} a {df_is.index[-1]} ({len(df_is)} barras)")
    print(f"OOS Range: {df_oos.index[0]} a {df_oos.index[-1]} ({len(df_oos)} barras)")

    # -------------------------------------------------------------------------
    # ETAPA A: Búsqueda amplia aislando el motor de señal (500 combinaciones)
    # -------------------------------------------------------------------------
    print("\n-------------------------------------------------------------------------")
    print(" ETAPA A: Generando 350 combinaciones aleatorias (semilla 42)...")
    print(" Executando backtests IS con lote fijo (0.03, sin compuesto, sin layering)...")
    print("-------------------------------------------------------------------------")

    combinations = generate_param_combinations(n_samples=350, seed=42)
    t0 = time.time()
    results_is = run_batch_backtests(combinations, df_is, profile_id=0, flat_sizing=True)
    t1 = time.time()
    print(f"Etapa A completada en {t1 - t0:.2f} segundos.")

    df_results_is = pd.DataFrame(results_is)
    df_results_is.to_csv(os.path.join(out_dir, "etapa_a_all_combinations_is.csv"), index=False)
    print(f"Resultados IS completos guardados en {out_dir}/etapa_a_all_combinations_is.csv")

    # Selección de los 20 mejores candidatos de IS
    # Si ningún candidato supera OnTester score > 0, seleccionar por Profit Factor descendente, luego menor Drawdown.
    has_positive_ontester = (df_results_is['ontester_score'] > 0).any()
    if has_positive_ontester:
        df_top20_is = df_results_is.sort_values(by=['ontester_score', 'profit_factor', 'net_profit'], ascending=False).head(20).copy()
    else:
        df_top20_is = df_results_is.sort_values(by=['profit_factor', 'net_profit'], ascending=False).head(20).copy()

    print("\nEvaluando top 20 candidatos en Out-Of-Sample (OOS)...")
    top20_combos = df_top20_is.to_dict('records')
    results_top20_oos = run_batch_backtests(top20_combos, df_oos, profile_id=0, flat_sizing=True)

    df_top20_oos = pd.DataFrame(results_top20_oos)

    # Merge IS y OOS para comparación walk-forward
    top20_comparison = []
    for _, is_row in df_top20_is.iterrows():
        pid = is_row['param_id']
        oos_row = df_top20_oos[df_top20_oos['param_id'] == pid].iloc[0]

        pf_is = is_row['profit_factor']
        pf_oos = oos_row['profit_factor']
        dd_is = is_row['max_dd_pct']
        dd_oos = oos_row['max_dd_pct']

        pass_pf = pf_oos >= (0.6 * pf_is)
        pass_dd = dd_oos <= (1.5 * dd_is)
        pass_walk_forward = pass_pf and pass_dd

        comp = {
            'param_id': pid,
            'InpThreshold': is_row['InpThreshold'],
            'InpW_RSI': is_row['InpW_RSI'],
            'InpW_CCI': is_row['InpW_CCI'],
            'InpW_Slope': is_row['InpW_Slope'],
            'InpW_Return': is_row['InpW_Return'],
            'InpW_Trend': is_row['InpW_Trend'],
            'InpSL_ATR': is_row['InpSL_ATR'],
            'InpTP_R': is_row['InpTP_R'],
            'IS_Trades': is_row['trades'],
            'IS_NetProfit': is_row['net_profit'],
            'IS_PF': is_row['profit_factor'],
            'IS_WinRate': is_row['win_rate'],
            'IS_MaxDD': is_row['max_dd_pct'],
            'IS_Sharpe': is_row['sharpe_ratio'],
            'IS_OnTester': is_row['ontester_score'],
            'OOS_Trades': oos_row['trades'],
            'OOS_NetProfit': oos_row['net_profit'],
            'OOS_PF': oos_row['profit_factor'],
            'OOS_WinRate': oos_row['win_rate'],
            'OOS_MaxDD': oos_row['max_dd_pct'],
            'OOS_Sharpe': oos_row['sharpe_ratio'],
            'OOS_OnTester': oos_row['ontester_score'],
            'Pass_PF': pass_pf,
            'Pass_DD': pass_dd,
            'Pass_WalkForward': pass_walk_forward
        }
        top20_comparison.append(comp)

    df_top20_comp = pd.DataFrame(top20_comparison)
    df_top20_comp.to_csv(os.path.join(out_dir, "etapa_a_top_candidates_is_oos.csv"), index=False)
    print(f"Top 20 candidatos guardados en {out_dir}/etapa_a_top_candidates_is_oos.csv")

    # -------------------------------------------------------------------------
    # ETAPA B: Interacción Señal x Money Management (4 perfiles)
    # -------------------------------------------------------------------------
    print("\n-------------------------------------------------------------------------")
    print(" ETAPA B: Evaluando los 5 mejores candidatos bajo los 4 Perfiles de Riesgo...")
    print("-------------------------------------------------------------------------")

    # Seleccionar top 5 candidatos por consistencia OOS/IS o mejor OOS PF
    df_top5_candidates = df_top20_comp.sort_values(by=['Pass_WalkForward', 'OOS_PF', 'IS_PF'], ascending=[False, False, False]).head(5).copy()

    profiles = [
        (0, "MANUAL"),
        (1, "CONSERVADOR"),
        (2, "BALANCEADO"),
        (3, "AGRESIVO")
    ]

    etapa_b_results = []

    for _, cand in df_top5_candidates.iterrows():
        combo = cand.to_dict()
        pid = combo['param_id']
        print(f"\nProbando Candidato ID {pid} (IS PF: {combo['IS_PF']}, OOS PF: {combo['OOS_PF']})...")

        for p_id, p_name in profiles:
            # Run IS with profile real sizing & layering
            res_is = _run_single_backtest((combo, df_is, p_id, False))
            # Run OOS with profile real sizing & layering
            res_oos = _run_single_backtest((combo, df_oos, p_id, False))

            rec = {
                'param_id': pid,
                'profile_id': p_id,
                'profile_name': p_name,
                'InpThreshold': combo['InpThreshold'],
                'InpW_RSI': combo['InpW_RSI'],
                'InpW_CCI': combo['InpW_CCI'],
                'InpW_Slope': combo['InpW_Slope'],
                'InpW_Return': combo['InpW_Return'],
                'InpW_Trend': combo['InpW_Trend'],
                'InpSL_ATR': combo['InpSL_ATR'],
                'InpTP_R': combo['InpTP_R'],
                'IS_Trades': res_is['trades'],
                'IS_NetProfit': res_is['net_profit'],
                'IS_PF': res_is['profit_factor'],
                'IS_WinRate': res_is['win_rate'],
                'IS_MaxDD': res_is['max_dd_pct'],
                'IS_Sharpe': res_is['sharpe_ratio'],
                'IS_OnTester': res_is['ontester_score'],
                'OOS_Trades': res_oos['trades'],
                'OOS_NetProfit': res_oos['net_profit'],
                'OOS_PF': res_oos['profit_factor'],
                'OOS_WinRate': res_oos['win_rate'],
                'OOS_MaxDD': res_oos['max_dd_pct'],
                'OOS_Sharpe': res_oos['sharpe_ratio'],
                'OOS_OnTester': res_oos['ontester_score']
            }
            etapa_b_results.append(rec)
            print(f"  Profile {p_name:<12} | IS Net: {res_is['net_profit']:>10.2f} (PF {res_is['profit_factor']:.2f}, DD {res_is['max_dd_pct']:.1f}%) | OOS Net: {res_oos['net_profit']:>10.2f} (PF {res_oos['profit_factor']:.2f}, DD {res_oos['max_dd_pct']:.1f}%)")

    df_etapa_b = pd.DataFrame(etapa_b_results)
    df_etapa_b.to_csv(os.path.join(out_dir, "etapa_b_candidates_x_profiles.csv"), index=False)
    print(f"\nResultados Etapa B guardados en {out_dir}/etapa_b_candidates_x_profiles.csv")

    print("\n=== Ciclo 3 completado exitosamente ===")

if __name__ == "__main__":
    main()
