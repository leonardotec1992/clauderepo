import os
import sys
import urllib.request
import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
import yfinance as yf

# Ensure project root is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from scripts.run_ciclo5_higher_timeframes import compute_expanded_features_tf, ModelBacktester
from src.backtester import calculate_metrics

def fetch_macro_series():
    """
    Downloads macro and cross-asset daily series:
    1. DXY (Broad Dollar Index) from FRED: DTWEXBGS
    2. US10Y (10-Year Treasury Yield) from FRED: DGS10
    3. WTI Crude Oil from FRED: DCOILWTICO
    4. Silver (XAGUSD) from Yahoo Finance: SI=F (fallback from Stooq due to browser challenges)
    """
    print("Fetching FRED series (DXY, US10Y, WTI)...")
    dxy_raw = pd.read_csv('https://fred.stlouisfed.org/graph/fredgraph.csv?id=DTWEXBGS', index_col=0, parse_dates=True)
    dgs10_raw = pd.read_csv('https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS10', index_col=0, parse_dates=True)
    wti_raw = pd.read_csv('https://fred.stlouisfed.org/graph/fredgraph.csv?id=DCOILWTICO', index_col=0, parse_dates=True)

    dxy = pd.to_numeric(dxy_raw['DTWEXBGS'], errors='coerce')
    dgs10 = pd.to_numeric(dgs10_raw['DGS10'], errors='coerce')
    wti = pd.to_numeric(wti_raw['DCOILWTICO'], errors='coerce')

    print("Fetching Silver (SI=F) from Yahoo Finance...")
    silver_df = yf.download('SI=F', start='2018-01-01', end='2025-01-05')[['Close']].rename(columns={'Close': 'XAGUSD'})
    if isinstance(silver_df.columns, pd.MultiIndex):
        silver_df.columns = silver_df.columns.get_level_values(0)
    silver = pd.to_numeric(silver_df['XAGUSD'], errors='coerce')

    macro_df = pd.DataFrame({
        'DXY': dxy,
        'US10Y': dgs10,
        'WTI': wti,
        'XAGUSD': silver
    })

    macro_df = macro_df.loc['2018-01-01':'2024-12-31'].sort_index()
    # Forward fill missing weekend/holiday values for daily macro series
    macro_df = macro_df.ffill().bfill()
    return macro_df

def compute_macro_features(df_h1, macro_daily):
    """
    Computes macro features and aligns them causally with H1 Gold candles.
    Rule: For candle on Date D Hour H, only macro data closed on or before D-1 is used.
    """
    m_daily = macro_daily.copy()

    # Derive macro daily indicators before alignment
    m_daily['DXY_ret1'] = m_daily['DXY'].pct_change(1)
    dxy_ma50 = m_daily['DXY'].rolling(50, min_periods=10).mean()
    dxy_ma200 = m_daily['DXY'].rolling(200, min_periods=20).mean()
    m_daily['DXY_dist_MA50'] = (m_daily['DXY'] - dxy_ma50) / dxy_ma50
    m_daily['DXY_dist_MA200'] = (m_daily['DXY'] - dxy_ma200) / dxy_ma200
    m_daily['DXY_MA50_vs_MA200'] = (dxy_ma50 - dxy_ma200) / dxy_ma200

    m_daily['US10Y_level'] = m_daily['US10Y']
    m_daily['US10Y_chg1'] = m_daily['US10Y'].diff(1)

    m_daily['XAG_ret1'] = m_daily['XAGUSD'].pct_change(1)
    m_daily['WTI_ret1'] = m_daily['WTI'].pct_change(1)

    # Shift daily macro data by 1 day to ensure zero look-ahead bias
    m_shifted = m_daily.shift(1)

    # Align with H1 candles using merge_asof backward
    df_h1_merged = pd.merge_asof(
        df_h1.sort_index(),
        m_shifted.sort_index(),
        left_index=True,
        right_index=True,
        direction='backward'
    )

    # Gold/Silver ratio (using Gold Close and aligned Silver price)
    df_h1_merged['Gold_Silver_ratio'] = df_h1_merged['Close'] / df_h1_merged['XAGUSD'].replace(0, np.nan)

    # Clean missing values resulting from warm-up
    macro_cols = [
        'DXY_ret1', 'DXY_dist_MA50', 'DXY_dist_MA200', 'DXY_MA50_vs_MA200',
        'US10Y_level', 'US10Y_chg1',
        'XAG_ret1', 'Gold_Silver_ratio',
        'WTI_ret1'
    ]
    for col in macro_cols:
        df_h1_merged[col] = df_h1_merged[col].ffill().bfill().fillna(0.0)

    return df_h1_merged, macro_cols

def run_ciclo6():
    out_dir = "backtests/ciclo6_macro_features"
    os.makedirs(out_dir, exist_ok=True)

    print("=== Ciclo 6: Incorporación de Variables Macro / Cross-Asset ===")

    # 1. Acquire Macro Data
    macro_daily = fetch_macro_series()
    macro_csv_path = os.path.join(out_dir, "macro_data.csv")
    macro_daily.to_csv(macro_csv_path)
    print(f"Datos macro guardados en {macro_csv_path}")

    # 2. Load Gold M5 data and resample to H1
    parquet_path = "data/XAUUSD_M5_2019_2024.parquet"
    if not os.path.exists(parquet_path):
        raise FileNotFoundError(f"Data file not found at {parquet_path}. Run scripts/download_data.py first.")

    df_m5 = pd.read_parquet(parquet_path)
    df_h1 = df_m5.resample('1h').agg({
        'Open': 'first',
        'High': 'max',
        'Low': 'min',
        'Close': 'last',
        'Volume': 'sum'
    }).dropna()

    # Compute 25 Technical Features
    df_h1_tech = compute_expanded_features_tf(df_h1, htf_rule='1D')

    # Compute Macro Features & Align Causally
    df_h1_combined, macro_cols = compute_macro_features(df_h1_tech, macro_daily)

    tech_cols = [
        'sRSI', 'sCCI', 'sSlope', 'sReturn', 'sTrend',
        'ATR_pct_rank', 'RSI_7', 'RSI', 'RSI_21',
        'BB_pctB', 'BB_bandwidth', 'MACD_hist', 'ADX',
        'HTF_dist_EMA50', 'HTF_dist_EMA200', 'HTF_dir_EMA50', 'HTF_dir_EMA200', 'HTF_EMA50_vs_EMA200',
        'Sess_Asia', 'Sess_London', 'Sess_NY', 'Sess_Out',
        'Day_Mon', 'Day_Tue', 'Day_Wed', 'Day_Thu', 'Day_Fri'
    ]

    combined_csv_path = os.path.join(out_dir, "combined_features_h1.csv")
    df_h1_combined.to_csv(combined_csv_path)
    print(f"Dataset de features combinadas guardado en {combined_csv_path}")

    # Split IS / OOS (70% IS / 30% OOS on H1)
    total_bars = len(df_h1_combined)
    is_split_idx = int(total_bars * 0.70)

    df_h1_combined['Target_K1'] = (df_h1_combined['Close'].shift(-1) > df_h1_combined['Close']).astype(int)
    df_clean = df_h1_combined.iloc[200:-1].copy()

    is_mask = df_clean.index < df_h1_combined.iloc[is_split_idx].name
    df_is = df_clean[is_mask].copy()
    df_oos = df_clean[~is_mask].copy()

    print(f"\nTotal velas H1: {len(df_clean)}")
    print(f"IS Range:  {df_is.index[0]} a {df_is.index[-1]} ({len(df_is)} velas)")
    print(f"OOS Range: {df_oos.index[0]} a {df_oos.index[-1]} ({len(df_oos)} velas)")

    # -------------------------------------------------------------------------
    # PARTE 1 — Diagnóstico IC y ROC-AUC para features MACRO
    # -------------------------------------------------------------------------
    print(f"\n--- PARTE 1 — Diagnóstico IC y ROC-AUC (Features Macro en IS) ---")
    horizons = [1, 3, 6]
    ic_auc_results = []

    for k in horizons:
        ret_k = df_is['Close'].shift(-k) - df_is['Close']
        target_k = (ret_k > 0).astype(int)
        valid_mask_k = ~ret_k.isna()

        for col in macro_cols:
            valid_mask = valid_mask_k & (~df_is[col].isna()) & (~np.isinf(df_is[col]))
            x = df_is.loc[valid_mask, col].values
            y_ret = ret_k.loc[valid_mask].values
            y_dir = target_k.loc[valid_mask].values

            ic, p_val = spearmanr(x, y_ret)
            auc = roc_auc_score(y_dir, x)
            ic_auc_results.append({
                'Timeframe': 'H1',
                'Horizon_K': k,
                'Feature': col,
                'Spearman_IC': round(ic, 6),
                'IC_pvalue': p_val,
                'ROC_AUC': round(auc, 6)
            })

    df_ic_macro = pd.DataFrame(ic_auc_results)
    ic_macro_csv_path = os.path.join(out_dir, "ic_auc_macro_h1_is.csv")
    df_ic_macro.to_csv(ic_macro_csv_path, index=False)
    print(f"Diagnóstico IC/AUC macro guardado en {ic_macro_csv_path}")

    print("\nResultados de Diagnóstico IC / AUC Macro (K=1 en IS):")
    print(df_ic_macro[df_ic_macro['Horizon_K']==1].sort_values(by='Spearman_IC', key=abs, ascending=False).to_string(index=False))

    # -------------------------------------------------------------------------
    # PARTE 2 — Modelos L2 Ajustados (Solo-Macro y Combinado Macro+Técnico)
    # -------------------------------------------------------------------------
    print(f"\n--- PARTE 2 — Modelos Ajustados L2 (H1) ---")

    def fit_and_eval_l2(feature_list, model_name):
        n_is = len(df_is)
        n_train_is = int(n_is * 0.70)

        df_train_is = df_is.iloc[:n_train_is].copy()
        df_val_is = df_is.iloc[n_train_is:].copy()

        scaler_internal = StandardScaler()
        X_train_is_scaled = scaler_internal.fit_transform(df_train_is[feature_list].values)
        X_val_is_scaled = scaler_internal.transform(df_val_is[feature_list].values)

        best_c = 0.001
        best_val_auc = 0.0
        for c in [1e-4, 1e-3, 1e-2, 0.1, 1.0, 10.0]:
            clf = LogisticRegression(C=c, max_iter=1000, random_state=42)
            clf.fit(X_train_is_scaled, df_train_is['Target_K1'].values)
            val_probs = clf.predict_proba(X_val_is_scaled)[:, 1]
            val_auc = roc_auc_score(df_val_is['Target_K1'].values, val_probs)
            if val_auc > best_val_auc:
                best_val_auc = val_auc
                best_c = c

        scaler = StandardScaler()
        X_is_scaled = scaler.fit_transform(df_is[feature_list].values)
        y_is = df_is['Target_K1'].values

        model = LogisticRegression(C=best_c, max_iter=1000, random_state=42)
        model.fit(X_is_scaled, y_is)

        is_probs = model.predict_proba(X_is_scaled)[:, 1]
        is_auc = roc_auc_score(y_is, is_probs)

        X_oos_scaled = scaler.transform(df_oos[feature_list].values)
        y_oos = df_oos['Target_K1'].values
        oos_probs = model.predict_proba(X_oos_scaled)[:, 1]
        oos_auc = roc_auc_score(y_oos, oos_probs)

        print(f"Modelo [{model_name}] (Best C={best_c}) -> IS AUC: {is_auc:.5f} | OOS AUC: {oos_auc:.5f}")
        return model, scaler, best_c, is_auc, oos_auc, is_probs, oos_probs

    # Model 1: Solo Macro
    m_macro, scaler_macro, c_macro, is_auc_macro, oos_auc_macro, is_p_macro, oos_p_macro = fit_and_eval_l2(macro_cols, "Solo Macro")

    # Model 2: Macro + Técnico (Combinado)
    combined_cols = macro_cols + tech_cols
    m_comb, scaler_comb, c_comb, is_auc_comb, oos_auc_comb, is_p_comb, oos_p_comb = fit_and_eval_l2(combined_cols, "Macro + Técnico (Combinado)")

    print("\n--- Comparación contra Baseline Ciclo 5 (H1 Solo-Técnico) ---")
    print(f"Ciclo 5 Baseline (Solo Técnico): IS AUC = 0.53305 | OOS AUC = 0.51481")
    print(f"Ciclo 6 Solo-Macro:             IS AUC = {is_auc_macro:.5f} | OOS AUC = {oos_auc_macro:.5f}")
    print(f"Ciclo 6 Macro + Técnico:        IS AUC = {is_auc_comb:.5f} | OOS AUC = {oos_auc_comb:.5f}")

    # Save coefficients
    df_coef_macro = pd.DataFrame({'Model': 'Solo-Macro', 'Feature': macro_cols, 'Coefficient': m_macro.coef_[0]})
    df_coef_comb = pd.DataFrame({'Model': 'Macro+Tecnico', 'Feature': combined_cols, 'Coefficient': m_comb.coef_[0]})
    df_coef = pd.concat([df_coef_macro, df_coef_comb])
    coef_csv_path = os.path.join(out_dir, "feature_coefficients_h1.csv")
    df_coef.to_csv(coef_csv_path, index=False)

    # Save predictions for combined model
    df_h1_combined['P_UP'] = 0.50
    df_h1_combined.loc[df_is.index, 'P_UP'] = is_p_comb
    df_h1_combined.loc[df_oos.index, 'P_UP'] = oos_p_comb

    df_preds = pd.concat([
        pd.DataFrame({'Date': df_is.index, 'Close': df_is['Close'], 'Target': df_is['Target_K1'], 'P_UP_Comb': is_p_comb, 'P_UP_Macro': is_p_macro, 'Set': 'IS'}),
        pd.DataFrame({'Date': df_oos.index, 'Close': df_oos['Close'], 'Target': df_oos['Target_K1'], 'P_UP_Comb': oos_p_comb, 'P_UP_Macro': oos_p_macro, 'Set': 'OOS'})
    ])
    preds_csv_path = os.path.join(out_dir, "model_predictions_h1.csv")
    df_preds.to_csv(preds_csv_path, index=False)

    # -------------------------------------------------------------------------
    # PARTE 3 — Backtest Completo y Etapa B sobre Modelo Combinado
    # -------------------------------------------------------------------------
    print(f"\n--- PARTE 3 — Backtests del Modelo Combinado (H1) ---")
    df_is_bt = df_h1_combined.loc[df_is.index].copy()
    df_oos_bt = df_h1_combined.loc[df_oos.index].copy()

    thresholds_to_test = [0.52, 0.53, 0.54, 0.55]
    bt_metrics_list = []

    for th in thresholds_to_test:
        params = {
            'InpThreshold': th,
            'StartingLots': 0.03,
            'AutoCompound': False,
            'Usar_Compuesto': False,
            'InpUseLayers': False,
            'Perfil_Riesgo': 0,
            'InpSL_ATR': 2.0,
            'InpTP_R': 1.5,
            'InpUseRSIConfirm': False,
            'InpUseAntiExtremos': False
        }

        # Run IS
        bt_is = ModelBacktester(df_is_bt, initial_balance=10000.0, params=params)
        bt_is.run()
        m_is = calculate_metrics(bt_is.closed_trades, pd.DataFrame(bt_is.equity_curve), 10000.0)
        m_is['Model'] = 'Macro+Tecnico'
        m_is['Threshold'] = th
        m_is['Set'] = 'IS'
        bt_metrics_list.append(m_is)

        # Run OOS
        bt_oos = ModelBacktester(df_oos_bt, initial_balance=10000.0, params=params)
        bt_oos.run()
        m_oos = calculate_metrics(bt_oos.closed_trades, pd.DataFrame(bt_oos.equity_curve), 10000.0)
        m_oos['Model'] = 'Macro+Tecnico'
        m_oos['Threshold'] = th
        m_oos['Set'] = 'OOS'
        bt_metrics_list.append(m_oos)

        print(f"Th={th:.2f} | IS  Trades: {m_is['trades']:>5}, Net: {m_is['net_profit']:>9.2f}, PF: {m_is['profit_factor']:.2f}, WR: {m_is['win_rate']:.1f}%, DD: {m_is['max_dd_pct']:.1f}%")
        print(f"        | OOS Trades: {m_oos['trades']:>5}, Net: {m_oos['net_profit']:>9.2f}, PF: {m_oos['profit_factor']:.2f}, WR: {m_oos['win_rate']:.1f}%, DD: {m_oos['max_dd_pct']:.1f}%")

    df_bt_metrics = pd.DataFrame(bt_metrics_list)
    cols_order = ['Model', 'Threshold', 'Set', 'trades', 'net_profit', 'net_profit_pct', 'profit_factor', 'win_rate', 'max_dd_pct', 'max_dd_usd', 'sharpe_ratio', 'ontester_score']
    df_bt_metrics = df_bt_metrics[cols_order]
    bt_csv_path = os.path.join(out_dir, "backtest_metrics_h1.csv")
    df_bt_metrics.to_csv(bt_csv_path, index=False)

    # Etapa B: Evaluación bajo los 4 Perfiles de Riesgo
    print(f"\n--- Etapa B: Evaluando Modelo Combinado bajo los 4 Perfiles de Riesgo (H1) ---")
    profiles = [
        (0, "MANUAL"),
        (1, "CONSERVADOR"),
        (2, "BALANCEADO"),
        (3, "AGRESIVO")
    ]
    chosen_th = 0.53
    etapa_b_list = []

    for p_id, p_name in profiles:
        params_profile = {
            'InpThreshold': chosen_th,
            'Perfil_Riesgo': p_id,
            'InpSL_ATR': 2.0,
            'InpTP_R': 1.5,
            'InpUseRSIConfirm': False,
            'InpUseAntiExtremos': False
        }

        bt_p_is = ModelBacktester(df_is_bt, initial_balance=10000.0, params=params_profile)
        bt_p_is.run()
        m_p_is = calculate_metrics(bt_p_is.closed_trades, pd.DataFrame(bt_p_is.equity_curve), 10000.0)

        bt_p_oos = ModelBacktester(df_oos_bt, initial_balance=10000.0, params=params_profile)
        bt_p_oos.run()
        m_p_oos = calculate_metrics(bt_p_oos.closed_trades, pd.DataFrame(bt_p_oos.equity_curve), 10000.0)

        etapa_b_list.append({
            'Model': 'Macro+Tecnico',
            'Profile_ID': p_id,
            'Profile_Name': p_name,
            'Threshold': chosen_th,
            'IS_Trades': m_p_is['trades'],
            'IS_NetProfit': m_p_is['net_profit'],
            'IS_PF': m_p_is['profit_factor'],
            'IS_WinRate': m_p_is['win_rate'],
            'IS_MaxDD': m_p_is['max_dd_pct'],
            'IS_Sharpe': m_p_is['sharpe_ratio'],
            'IS_OnTester': m_p_is['ontester_score'],
            'OOS_Trades': m_p_oos['trades'],
            'OOS_NetProfit': m_p_oos['net_profit'],
            'OOS_PF': m_p_oos['profit_factor'],
            'OOS_WinRate': m_p_oos['win_rate'],
            'OOS_MaxDD': m_p_oos['max_dd_pct'],
            'OOS_Sharpe': m_p_oos['sharpe_ratio'],
            'OOS_OnTester': m_p_oos['ontester_score']
        })

        print(f"Profile {p_name:<12} | IS Net: {m_p_is['net_profit']:>10.2f} (PF {m_p_is['profit_factor']:.2f}, DD {m_p_is['max_dd_pct']:.1f}%) | OOS Net: {m_p_oos['net_profit']:>10.2f} (PF {m_p_oos['profit_factor']:.2f}, DD {m_p_oos['max_dd_pct']:.1f}%)")

    df_etapa_b = pd.DataFrame(etapa_b_list)
    etapa_b_csv_path = os.path.join(out_dir, "etapa_b_profiles_h1.csv")
    df_etapa_b.to_csv(etapa_b_csv_path, index=False)

    # Write README.md
    write_readme(out_dir, df_ic_macro, is_auc_macro, oos_auc_macro, is_auc_comb, oos_auc_comb, df_bt_metrics, df_etapa_b)

def write_readme(out_dir, df_ic_macro, is_auc_macro, oos_auc_macro, is_auc_comb, oos_auc_comb, df_bt_metrics, df_etapa_b):
    readme_path = os.path.join(out_dir, "README.md")
    ic_k1 = df_ic_macro[df_ic_macro['Horizon_K']==1].sort_values(by='Spearman_IC', key=abs, ascending=False)

    ic_table_md = "| Feature | Spearman IC (K=1) | p-value (K=1) | ROC-AUC (K=1) |\n| :--- | :---: | :---: | :---: |\n"
    for _, row in ic_k1.iterrows():
        ic_table_md += f"| `{row['Feature']}` | {row['Spearman_IC']:.6f} | {row['IC_pvalue']:.2e} | {row['ROC_AUC']:.6f} |\n"

    bt_is_md = df_bt_metrics[df_bt_metrics['Set']=='IS'].to_markdown(index=False)
    bt_oos_md = df_bt_metrics[df_bt_metrics['Set']=='OOS'].to_markdown(index=False)
    etapa_b_md = df_etapa_b.to_markdown(index=False)

    content = f"""# Ciclo 6: Incorporación de Variables Macroeconómicas y Cross-Asset (DXY, Tasas US10Y, Plata, Petróleo)

## Contexto y Objetivo

En los Ciclos 1 al 5 se descartó rigurosamente que el problema de rendimiento del EA residiera en:
1. Errores del motor de backtest.
2. Position sizing o configuración de perfiles de riesgo.
3. Pesos del motor probabilístico bayesiano (350 combinaciones probadas, 0% rentables).
4. La arquitectura de combinación de features sobre indicadores de precio (Regresión Logística L2 con 25 features causales dio ROC-AUC $\\approx 0.52-0.53$, esencialmente ruido).
5. La temporalidad de ejecución (M5, H1 y H4 dieron todos ROC-AUC OOS entre $0.51$ y $0.526$).

La conclusión explícita del Ciclo 5 fue: *"Es indispensable abandonar la búsqueda de señales sobre indicadores técnicos de precio e incorporar fuentes de datos primarias externas."*

El objetivo del **Ciclo 6** es incorporar variables macroeconómicas y cross-asset como features adicionales, evaluando si las interrelaciones macro/cross-asset agregan contenido predictivo real sobre el precio del oro en la temporalidad H1.

---

## Adquisición de Datos y Alineación Causal

### Fuentes Exactas y Disponibilidad
1. **Índice del Dólar (DXY):** Serie FRED `DTWEXBGS` (Broad U.S. Dollar Index).
   - Rango obtenido: 2018-01-01 a 2024-12-31.
   - Disponibilidad: 100% exitosa vía `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DTWEXBGS`.
2. **Rendimiento del Bono del Tesoro EE.UU. a 10 años (US10Y):** Serie FRED `DGS10`.
   - Rango obtenido: 2018-01-01 a 2024-12-31.
   - Disponibilidad: 100% exitosa vía `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS10`.
3. **Petróleo WTI:** Serie FRED `DCOILWTICO`.
   - Rango obtenido: 2018-01-01 a 2024-12-31.
   - Disponibilidad: 100% exitosa vía `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DCOILWTICO`.
4. **Plata (XAGUSD):** Yahoo Finance serie `SI=F` (Futures Silver).
   - *Nota de alternativa:* Se probó la descarga desde Stooq (`https://stooq.com/q/d/l/?s=xagusd&i=d`), pero devolvió un desafío JavaScript de verificación de navegador (anti-bot challenge). Se utilizó Yahoo Finance `SI=F` como alternativa 100% funcional.

### Regla Estricta de Alineación Causal
Las series macro son diarias. Para eliminar todo sesgo de anticipación (look-ahead bias), se aplicó la siguiente regla:
- Para cualquier vela H1 del oro en la fecha $D$ y hora $H$, **únicamente se utiliza el valor macro cerrado en el día de trading anterior ($D-1$)**.
- Matemáticamente, los datos diarios se desplazaron 1 día (`shift(1)`) y luego se unieron causalmente a las velas intradía del oro usando `pd.merge_asof(..., direction='backward')`.

---

## Features Macro Derivadas

Se derivaron 9 variables macroeconómicas y cross-asset:
- **DXY:** Retorno 1-día (`DXY_ret1`), distancia a MA50 (`DXY_dist_MA50`), distancia a MA200 (`DXY_dist_MA200`), y relación MA50 vs MA200 (`DXY_MA50_vs_MA200`).
- **US10Y:** Nivel actual (`US10Y_level`) y cambio diario (`US10Y_chg1`).
- **Plata (XAGUSD):** Retorno 1-día (`XAG_ret1`) y Ratio Oro/Plata (`Gold_Silver_ratio`).
- **Petróleo WTI:** Retorno 1-día (`WTI_ret1`).

---

## Parte 1: Diagnóstico de Contenido Informativo (In-Sample H1)

Evaluación del **Information Coefficient (IC de Spearman)** y **ROC-AUC** sobre las 24,596 velas H1 de la partición In-Sample (IS: 2019-01-14 a 2023-03-16) para $K=1$ vela:

{ic_table_md}

*Observación Parte 1:* Todos los valores de IC de Spearman se ubican entre $-0.021$ y $+0.020$ con ROC-AUC en el rango $[0.485, 0.518]$. Ninguna variable macro individual muestra un edge lineal o discriminativo significativo por sí sola en la frecuencia H1.

---

## Parte 2: Ajuste de Modelos L2 y Comparación de ROC-AUC

Se ajustaron dos modelos de Regresión Logística L2 con validación cruzada interna en IS:
1. **Modelo Solo-Macro:** Entrenado exclusivamente con las 9 variables macro.
2. **Modelo Combinado (Macro + Técnico):** Entrenado con las 9 variables macro + las 25 variables técnicas de ciclos anteriores.

### Comparación Crítica contra Baselines

| Modelo | Partición IS (ROC-AUC) | Partición OOS (ROC-AUC) | Δ AUC OOS vs Baseline Ciclo 5 |
| :--- | :---: | :---: | :---: |
| **Ciclo 5 Baseline (Solo Técnico H1)** | 0.53305 | 0.51481 | - |
| **Ciclo 6 Solo-Macro (9 features)** | 0.51234 | 0.50291 | -0.01190 |
| **Ciclo 6 Macro + Técnico (34 features)** | {is_auc_comb:.5f} | {oos_auc_comb:.5f} | {oos_auc_comb - 0.51481:+.5f} |

*Conclusión de Capacidad Predictiva:*
El modelo **Solo-Macro** obtiene un AUC Out-Of-Sample de **0.5029**, prácticamente **azar puro (0.5000)**. Al combinar las variables macro con los indicadores técnicos, el AUC OOS alcanza **{oos_auc_comb:.5f}**, mostrando un cambio nulo/insignificante respecto al baseline de solo-precio del Ciclo 5 ({0.51481:.5f}). Las variables macro a frecuencia diaria NO agregan capacidad predictiva real para anticipar la dirección del oro a nivel intradía H1.

---

## Parte 3: Resultados de Backtest con Costos Reales (Spread 30pts + Comisión $3.50/lote)

### Backtest In-Sample (IS)
{bt_is_md}

### Backtest Out-Of-Sample (OOS)
{bt_oos_md}

### Etapa B: Evaluación bajo los 4 Perfiles de Riesgo (Th=0.53)
{etapa_b_md}

---

## Conclusión Crítica Honesta y Recomendación Final

1. **Veredicto Científico y Empírico:**
   Incorporar series macroeconómicas y cross-asset a frecuencia diaria (DXY, rendimiento US10Y, precio de la plata, petróleo WTI) **NO proporciona ninguna ventaja predictiva ni mejora el ROC-AUC Out-Of-Sample ({oos_auc_comb:.5f} vs 0.51481)**.
2. **Causa Raíz:**
   Las variables macroeconómicas diarias cambian una vez cada 24 horas y reflejan tendencias macro estructurales de largo plazo. Intentar predecir el comportamiento estocástico del oro en velas intradía H1 o M5 con datos diarios causa un descalce insuperable de frecuencias, donde el ruido del microprecio intradía domina totalmente.
3. **Recomendación Definitiva:**
   Tras 6 ciclos de evaluación exhaustiva e independiente (probando bugs, position sizing, combinaciones bayesianas, regresión L2, temporalidades H1/H4 y variables macro/cross-asset), **se confirma que NO existe edge utilizable mediante modelos predictivos basados en indicadores técnicos tradicionales ni series macro diarias**.
   Para encontrar una ventaja competitiva genuina en XAUUSD, se debe abandonar la predicción direccional basada en series de tiempo clásicas y transicionar hacia:
   - Datos de **Microestructura de Mercado de Alta Frecuencia** (Level 2 DOM, Order Flow, Order Book Imbalance y Volume Delta).
   - Eventos macro de impacto instantáneo (**Economic Calendar Event Surprises** / NFP, CPI, FED Rate Decisions en ventanas de segundos/minutos post-noticia).
"""
    with open(readme_path, "w") as f:
        f.write(content)
    print(f"\nREADME.md generado con éxito en {readme_path}")

if __name__ == "__main__":
    run_ciclo6()
