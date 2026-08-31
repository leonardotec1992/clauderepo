import os
import sys
import time
import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score

# Ensure project root is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.backtester import calculate_indicators, Backtester, calculate_metrics, Position

def calc_rsi(series, period=14):
    delta = series.diff()
    gain = delta.clip(lower=0).ewm(alpha=1/period, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1/period, adjust=False).mean()
    rs = gain / loss.replace(0, np.nan)
    return (100 - (100 / (1 + rs))).fillna(50.0)

def calc_cci(df, period=14):
    tp = (df['High'] + df['Low'] + df['Close']) / 3.0
    tp_sma = tp.rolling(window=period).mean()
    mad = tp.rolling(window=period).apply(lambda x: np.mean(np.abs(x - np.mean(x))), raw=True)
    cci = (tp - tp_sma) / (0.015 * mad)
    return cci.fillna(0.0)

def calc_atr(df, period=14):
    tr1 = df['High'] - df['Low']
    tr2 = (df['High'] - df['Close'].shift(1)).abs()
    tr3 = (df['Low'] - df['Close'].shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    return tr.ewm(alpha=1/period, adjust=False).mean()

def calc_adx(df, period=14):
    high, low, close = df['High'], df['Low'], df['Close']
    up_move = high - high.shift(1)
    down_move = low.shift(1) - low
    plus_dm = pd.Series(np.where((up_move > down_move) & (up_move > 0), up_move, 0.0), index=df.index)
    minus_dm = pd.Series(np.where((down_move > up_move) & (down_move > 0), down_move, 0.0), index=df.index)
    atr = calc_atr(df, period)
    plus_di = 100 * (plus_dm.ewm(alpha=1/period, adjust=False).mean() / atr)
    minus_di = 100 * (minus_dm.ewm(alpha=1/period, adjust=False).mean() / atr)
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan)
    return dx.ewm(alpha=1/period, adjust=False).mean().fillna(0.0)

def compute_expanded_features_tf(df_tf, htf_rule='1D'):
    """
    Computes all 25 expanded features causally without lookahead for a given timeframe dataset:
    - 5 original features (sRSI, sCCI, sSlope, sReturn, sTrend)
    - Volatility: rolling percentile rank of ATR(14)
    - Multi-scale momentum: RSI(7), RSI(14), RSI(21)
    - Bollinger Bands (20,2): %B and bandwidth
    - MACD (12,26,9): histogram
    - ADX(14): continuous ADX
    - Higher timeframe trend: HTF (e.g., Daily D1) EMA50/EMA200 direction & distance (resampled causally)
    - Session dummies (Asia/London/NY/Out) and Day of week dummies
    """
    df = df_tf.copy()

    # Base indicators
    df['RSI'] = calc_rsi(df['Close'], 14)
    df['RSI_7'] = calc_rsi(df['Close'], 7)
    df['RSI_21'] = calc_rsi(df['Close'], 21)

    df['CCI'] = calc_cci(df, 14)
    df['ATR'] = calc_atr(df, 14)
    df['ADX'] = calc_adx(df, 14)

    df['EMA_100'] = df['Close'].ewm(span=100, adjust=False).mean()

    # Original 5 features
    df['sRSI'] = np.clip((50.0 - df['RSI']) / 50.0, -1.0, 1.0)
    df['sCCI'] = np.clip((-df['CCI']) / 150.0, -1.0, 1.0)
    df['sSlope'] = np.clip((df['RSI'] - df['RSI'].shift(1)) / 25.0, -1.0, 1.0)
    df['sReturn'] = np.clip((df['Close'] - df['Open']) / df['ATR'].replace(0, np.nan), -1.0, 1.0)
    df['sTrend'] = np.clip((df['Close'] - df['EMA_100']) / df['ATR'].replace(0, np.nan), -1.0, 1.0)

    # Volatility percentile
    df['ATR_pct_rank'] = df['ATR'].rolling(window=500, min_periods=20).rank(pct=True).fillna(0.5)

    # Bollinger Bands (20,2)
    sma20 = df['Close'].rolling(window=20).mean()
    std20 = df['Close'].rolling(window=20).std()
    upper20 = sma20 + 2 * std20
    lower20 = sma20 - 2 * std20
    df['BB_pctB'] = ((df['Close'] - lower20) / (upper20 - lower20).replace(0, np.nan)).fillna(0.5)
    df['BB_bandwidth'] = ((upper20 - lower20) / sma20.replace(0, np.nan)).fillna(0.0)

    # MACD (12, 26, 9)
    ema12 = df['Close'].ewm(span=12, adjust=False).mean()
    ema26 = df['Close'].ewm(span=26, adjust=False).mean()
    macd_line = ema12 - ema26
    signal_line = macd_line.ewm(span=9, adjust=False).mean()
    df['MACD_hist'] = (macd_line - signal_line).fillna(0.0)

    # Higher timeframe indicators (Resampled causally, shifted by 1 completed HTF bar)
    df_htf = df.resample(htf_rule).agg({'Open':'first', 'High':'max', 'Low':'min', 'Close':'last'}).dropna()
    df_htf['EMA_Fast'] = df_htf['Close'].ewm(span=50, adjust=False).mean()
    df_htf['EMA_Slow'] = df_htf['Close'].ewm(span=200, adjust=False).mean()
    df_htf['HTF_ATR14'] = calc_atr(df_htf, 14)

    df_htf_shifted = df_htf[['EMA_Fast', 'EMA_Slow', 'HTF_ATR14']].shift(1)
    df = pd.merge_asof(df, df_htf_shifted, left_index=True, right_index=True, direction='backward')

    # Assign fast and slow EMAs to DF for backtester filter checks
    df['EMA_Fast'] = df['EMA_Fast'].fillna(df['Close'])
    df['EMA_Slow'] = df['EMA_Slow'].fillna(df['Close'])

    df['HTF_dist_EMA50'] = ((df['Close'] - df['EMA_Fast']) / df['ATR'].replace(0, np.nan)).fillna(0.0)
    df['HTF_dist_EMA200'] = ((df['Close'] - df['EMA_Slow']) / df['ATR'].replace(0, np.nan)).fillna(0.0)
    df['HTF_dir_EMA50'] = np.sign(df['Close'] - df['EMA_Fast']).fillna(0.0)
    df['HTF_dir_EMA200'] = np.sign(df['Close'] - df['EMA_Slow']).fillna(0.0)
    df['HTF_EMA50_vs_EMA200'] = ((df['EMA_Fast'] - df['EMA_Slow']) / df['ATR'].replace(0, np.nan)).fillna(0.0)

    # Session dummies
    hours = df.index.hour
    df['Sess_Asia'] = np.where((hours >= 22) | (hours < 2), 1.0, 0.0)
    df['Sess_London'] = np.where((hours >= 2) & (hours < 11), 1.0, 0.0)
    df['Sess_NY'] = np.where((hours >= 8) & (hours < 11), 1.0, 0.0)
    df['Sess_Out'] = np.where((df['Sess_Asia']==0) & (df['Sess_London']==0) & (df['Sess_NY']==0), 1.0, 0.0)

    # Day of week dummies
    dayofweek = df.index.dayofweek
    df['Day_Mon'] = np.where(dayofweek == 0, 1.0, 0.0)
    df['Day_Tue'] = np.where(dayofweek == 1, 1.0, 0.0)
    df['Day_Wed'] = np.where(dayofweek == 2, 1.0, 0.0)
    df['Day_Thu'] = np.where(dayofweek == 3, 1.0, 0.0)
    df['Day_Fri'] = np.where(dayofweek == 4, 1.0, 0.0)

    return df

class ModelBacktester(Backtester):
    def run(self):
        point = 0.01
        spread_val = self.params['SpreadPts'] * point

        self.g_dayStamp = -1
        self.g_dayStartBal = self.initial_balance
        self.g_shieldTripped = False
        self.g_objTripped = False

        dates = list(self.df.index)
        opens = self.df['Open'].values
        highs = self.df['High'].values
        lows = self.df['Low'].values
        closes = self.df['Close'].values
        rsis = self.df['RSI'].values
        ccis = self.df['CCI'].values
        atrs = self.df['ATR'].values
        ema_fasts = self.df['EMA_Fast'].values
        ema_slows = self.df['EMA_Slow'].values
        adxs = self.df['ADX'].values
        p_up_arr = self.df['P_UP'].values

        dayofyears = self.df.index.dayofyear.values
        hours = self.df.index.hour.values
        n_bars = len(self.df)

        for i in range(1, n_bars):
            dt = dates[i]
            open_p = opens[i]
            high_p = highs[i]
            low_p = lows[i]
            close_p = closes[i]

            bid = open_p
            ask = open_p + spread_val

            day_of_year = dayofyears[i]
            if day_of_year != self.g_dayStamp:
                self.g_dayStamp = day_of_year
                self.g_dayStartBal = self.balance
                self.g_shieldTripped = False
                self.g_objTripped = False

            if self.balance <= 0 or self.equity <= 0:
                if self.positions:
                    self.close_all_positions(bid, ask, dt, 'Stop Out')
                self.balance = max(0.0, self.balance)
                self.equity = max(0.0, self.equity)
                self.equity_curve.append({'Date': dt, 'Balance': self.balance, 'Equity': self.equity})
                break

            floating_pnl = sum((bid - pos.open_price if pos.type == 'BUY' else pos.open_price - ask) * 100.0 * pos.lot for pos in self.positions)
            ganancia_hoy = (self.balance - self.g_dayStartBal) + floating_pnl
            day_start_bal = self.g_dayStartBal if self.g_dayStartBal > 0 else self.balance

            daily_dd_pct = max(0.0, -ganancia_hoy / day_start_bal * 100.0)
            daily_gain_pct = (ganancia_hoy / day_start_bal * 100.0) if day_start_bal > 0 else 0.0

            if self.params['Usar_Shield'] and not self.g_shieldTripped and daily_dd_pct >= self.g_shieldMax:
                self.g_shieldTripped = True
                self.close_all_positions(bid, ask, dt, 'Shield Tripped')
                floating_pnl = 0.0

            meta_pct = self.params['Objetivo_Diario'] if self.g_profile == 0 else self.g_objetivoPct
            if self.params['Usar_Objetivo'] and not self.g_objTripped and meta_pct > 0 and daily_gain_pct >= meta_pct:
                self.g_objTripped = True
                self.close_all_positions(bid, ask, dt, 'Daily Goal Met')
                floating_pnl = 0.0

            atr_now = atrs[i-1] if not pd.isna(atrs[i-1]) else 1.0
            self.manage_positions_bar(high_p, low_p, bid, ask, dt, atr_now, point)

            floating_pnl = sum((bid - pos.open_price if pos.type == 'BUY' else pos.open_price - ask) * 100.0 * pos.lot for pos in self.positions)
            current_equity = self.balance + floating_pnl
            self.equity = current_equity

            if self.balance <= 0 or current_equity <= 0:
                if self.positions:
                    self.close_all_positions(bid, ask, dt, 'Stop Out')
                self.balance = max(0.0, self.balance)
                self.equity = max(0.0, self.equity)
                self.equity_curve.append({'Date': dt, 'Balance': self.balance, 'Equity': self.equity})
                break

            self.equity_curve.append({'Date': dt, 'Balance': self.balance, 'Equity': current_equity})

            if self.params['Usar_Shield'] and self.g_shieldTripped: continue
            if self.params['Usar_Objetivo'] and self.g_objTripped: continue
            if not self.params['Operar_24H']:
                h = hours[i]
                p = self.params
                in_sess = False
                if p['Sesion_NuevaYork'] and (p['NY_Hora_Inicio'] <= h < p['NY_Hora_Cierre']): in_sess = True
                elif p['Sesion_Londres'] and (p['Londres_Hora_Inicio'] <= h < p['Londres_Hora_Cierre']): in_sess = True
                elif p['Sesion_Asia'] and (h >= p['Asia_Hora_Inicio'] or h < p['Asia_Hora_Cierre']): in_sess = True
                if not in_sess: continue

            atr_pts = atr_now / point
            if self.params['InpUseVolGate'] and (atr_pts < self.params['InpATRMinPts'] or atr_pts > self.params['InpATRMaxPts']):
                continue

            p_up = p_up_arr[i-1]
            rsi_now = rsis[i-1]
            cci_now = ccis[i-1]

            go_long = (p_up >= self.params['InpThreshold'])
            go_short = (p_up <= 1.0 - self.params['InpThreshold'])

            if not self.ema_allows(True, bid, ema_fasts[i], ema_slows[i]): go_long = False
            if not self.ema_allows(False, bid, ema_fasts[i], ema_slows[i]): go_short = False

            if self.params['InpUseRSIConfirm']:
                if rsi_now > self.params['InpRSI_LongMax']: go_long = False
                if rsi_now < self.params['InpRSI_ShortMin']: go_short = False

            if self.params['InpUseAntiExtremos']:
                if rsi_now > 75.0 and cci_now > 150.0: go_long = False
                if rsi_now < 25.0 and cci_now < -150.0: go_short = False

            n_pos = len(self.positions)
            if n_pos > 0 and not self.g_useLayers: continue
            if not self.adx_allows(adxs[i]): continue

            if self.params['Usar_Spread_Max'] and self.params['SpreadPts'] > self.params['Spread_Max']: continue
            if self.params['Usar_Margen'] and (self.balance <= 0 or self.equity <= 0): continue

            if n_pos == 0:
                sl_dist = atr_now * self.params['InpSL_ATR']
                if self.params['Max_SL_Puntos'] > 0 and (sl_dist / point) > self.params['Max_SL_Puntos']: continue
                tp_dist = self.params['TakeProfit'] * point if self.params['TakeProfit'] > 0 else sl_dist * self.params['InpTP_R']
                lot = self.calc_lot(self.balance, sl_dist)

                if go_long:
                    entry_price = ask
                    sl = entry_price - sl_dist
                    tp = entry_price + tp_dist
                    pos = Position(self.ticket_counter, 'BUY', entry_price, dt, lot, round(sl, 2), round(tp, 2))
                    self.ticket_counter += 1
                    self.positions.append(pos)
                elif go_short:
                    entry_price = bid
                    sl = entry_price + sl_dist
                    tp = entry_price - tp_dist
                    pos = Position(self.ticket_counter, 'SELL', entry_price, dt, lot, round(sl, 2), round(tp, 2))
                    self.ticket_counter += 1
                    self.positions.append(pos)
            elif self.g_useLayers:
                self.try_add_layer(p_up, ask, bid, atr_now, dt)

        if self.positions:
            last_dt = dates[-1]
            last_close = closes[-1]
            self.close_all_positions(last_close, last_close + spread_val, last_dt, 'End of Backtest')


def run_pipeline_for_timeframe(df_m5, resample_rule, tf_name, htf_rule, horizons, out_dir):
    print(f"\n=========================================================================")
    print(f" PROCESANDO TEMPORALIDAD {tf_name} (Resample: {resample_rule}, HTF: {htf_rule})")
    print(f"=========================================================================")

    # 1. Resample M5 to primary timeframe
    df_tf = df_m5.resample(resample_rule).agg({
        'Open': 'first',
        'High': 'max',
        'Low': 'min',
        'Close': 'last',
        'Volume': 'sum'
    }).dropna()

    print(f"Barras generadas para {tf_name}: {len(df_tf)}")

    # 2. Compute 25 features
    df = compute_expanded_features_tf(df_tf, htf_rule=htf_rule)

    feature_cols = [
        'sRSI', 'sCCI', 'sSlope', 'sReturn', 'sTrend',
        'ATR_pct_rank', 'RSI_7', 'RSI', 'RSI_21',
        'BB_pctB', 'BB_bandwidth', 'MACD_hist', 'ADX',
        'HTF_dist_EMA50', 'HTF_dist_EMA200', 'HTF_dir_EMA50', 'HTF_dir_EMA200', 'HTF_EMA50_vs_EMA200',
        'Sess_Asia', 'Sess_London', 'Sess_NY', 'Sess_Out',
        'Day_Mon', 'Day_Tue', 'Day_Wed', 'Day_Thu', 'Day_Fri'
    ]

    total_bars = len(df)
    is_split_idx = int(total_bars * 0.70)

    df['Target_K1'] = (df['Close'].shift(-1) > df['Close']).astype(int)
    df_clean = df.iloc[200:-1].copy() # Warmup for rolling features and valid target

    is_mask = df_clean.index < df.iloc[is_split_idx].name
    df_is = df_clean[is_mask].copy()
    df_oos = df_clean[~is_mask].copy()

    print(f"Total barras analizadas ({tf_name}): {len(df_clean)}")
    print(f"IS Range:  {df_is.index[0]} a {df_is.index[-1]} ({len(df_is)} barras)")
    print(f"OOS Range: {df_oos.index[0]} a {df_oos.index[-1]} ({len(df_oos)} barras)")

    # -------------------------------------------------------------------------
    # PARTE 1 — Diagnóstico de Contenido Informativo (IC y AUC en IS)
    # -------------------------------------------------------------------------
    print(f"\n--- PARTE 1 — Diagnóstico IC y ROC-AUC ({tf_name}) ---")
    ic_auc_results = []
    for k in horizons:
        ret_k = df_is['Close'].shift(-k) - df_is['Close']
        target_k = (ret_k > 0).astype(int)
        valid_mask_k = ~ret_k.isna()

        for col in feature_cols:
            valid_mask = valid_mask_k & (~df_is[col].isna()) & (~np.isinf(df_is[col]))
            x = df_is.loc[valid_mask, col].values
            y_ret = ret_k.loc[valid_mask].values
            y_dir = target_k.loc[valid_mask].values

            ic, p_val = spearmanr(x, y_ret)
            auc = roc_auc_score(y_dir, x)
            ic_auc_results.append({
                'Timeframe': tf_name,
                'Horizon_K': k,
                'Feature': col,
                'Spearman_IC': round(ic, 6),
                'IC_pvalue': p_val,
                'ROC_AUC': round(auc, 6)
            })

    df_ic_auc = pd.DataFrame(ic_auc_results)
    csv_ic_auc_path = os.path.join(out_dir, f"ic_auc_diagnosis_{tf_name.lower()}_is.csv")
    df_ic_auc.to_csv(csv_ic_auc_path, index=False)
    print(f"Diagnóstico IC/AUC guardado en {csv_ic_auc_path}")

    print(f"\nTop 10 Features por |IC| para horizon K={horizons[0]} ({tf_name}):")
    print(df_ic_auc[df_ic_auc['Horizon_K']==horizons[0]].sort_values(by='Spearman_IC', key=abs, ascending=False).head(10).to_string(index=False))

    # -------------------------------------------------------------------------
    # PARTE 2 — Ajuste de Modelo de Regresión Logística L2 en IS
    # -------------------------------------------------------------------------
    print(f"\n--- PARTE 2 — Modelo Ajustado L2 ({tf_name}) ---")
    n_is = len(df_is)
    n_train_is = int(n_is * 0.70)

    df_train_is = df_is.iloc[:n_train_is].copy()
    df_val_is = df_is.iloc[n_train_is:].copy()

    scaler_internal = StandardScaler()
    X_train_is_scaled = scaler_internal.fit_transform(df_train_is[feature_cols].values)
    X_val_is_scaled = scaler_internal.transform(df_val_is[feature_cols].values)

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

    print(f"Mejor parámetro C seleccionado en Val_IS ({tf_name}): {best_c} (Val AUC: {best_val_auc:.5f})")

    # Fit final model on full IS
    scaler = StandardScaler()
    X_is_scaled = scaler.fit_transform(df_is[feature_cols].values)
    y_is = df_is['Target_K1'].values

    model = LogisticRegression(C=best_c, max_iter=1000, random_state=42)
    model.fit(X_is_scaled, y_is)

    is_probs = model.predict_proba(X_is_scaled)[:, 1]
    is_auc = roc_auc_score(y_is, is_probs)

    X_oos_scaled = scaler.transform(df_oos[feature_cols].values)
    y_oos = df_oos['Target_K1'].values
    oos_probs = model.predict_proba(X_oos_scaled)[:, 1]
    oos_auc = roc_auc_score(y_oos, oos_probs)

    print(f"Modelo Final ({tf_name}) - AUC IS:  {is_auc:.5f}")
    print(f"Modelo Final ({tf_name}) - AUC OOS: {oos_auc:.5f}")

    # Save feature coefficients
    df_coef = pd.DataFrame({
        'Timeframe': tf_name,
        'Feature': feature_cols,
        'Coefficient': model.coef_[0],
        'Abs_Coef': np.abs(model.coef_[0])
    }).sort_values(by='Abs_Coef', ascending=False)

    csv_coef_path = os.path.join(out_dir, f"feature_coefficients_{tf_name.lower()}.csv")
    df_coef.to_csv(csv_coef_path, index=False)

    # Save predictions
    df['P_UP'] = 0.50
    df.loc[df_is.index, 'P_UP'] = is_probs
    df.loc[df_oos.index, 'P_UP'] = oos_probs

    df_pred_is = pd.DataFrame({'Date': df_is.index, 'Close': df_is['Close'], 'Target': y_is, 'P_UP': is_probs, 'Set': 'IS'})
    df_pred_oos = pd.DataFrame({'Date': df_oos.index, 'Close': df_oos['Close'], 'Target': y_oos, 'P_UP': oos_probs, 'Set': 'OOS'})
    df_preds = pd.concat([df_pred_is, df_pred_oos])
    csv_preds_path = os.path.join(out_dir, f"model_predictions_{tf_name.lower()}.csv")
    df_preds.to_csv(csv_preds_path, index=False)

    # -------------------------------------------------------------------------
    # Backtests de Señal Aislada (Lote fijo 0.03, sin compounding, sin layering)
    # -------------------------------------------------------------------------
    print(f"\n--- Evaluando Backtests del Modelo Ajustado ({tf_name}) ---")

    df_is_bt = df.loc[df_is.index].copy()
    df_oos_bt = df.loc[df_oos.index].copy()

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
        m_is['Timeframe'] = tf_name
        m_is['Threshold'] = th
        m_is['Set'] = 'IS'
        bt_metrics_list.append(m_is)

        # Run OOS
        bt_oos = ModelBacktester(df_oos_bt, initial_balance=10000.0, params=params)
        bt_oos.run()
        m_oos = calculate_metrics(bt_oos.closed_trades, pd.DataFrame(bt_oos.equity_curve), 10000.0)
        m_oos['Timeframe'] = tf_name
        m_oos['Threshold'] = th
        m_oos['Set'] = 'OOS'
        bt_metrics_list.append(m_oos)

        print(f"Th={th:.2f} | IS  Trades: {m_is['trades']:>5}, Net: {m_is['net_profit']:>9.2f}, PF: {m_is['profit_factor']:.2f}, WR: {m_is['win_rate']:.1f}%, DD: {m_is['max_dd_pct']:.1f}%")
        print(f"        | OOS Trades: {m_oos['trades']:>5}, Net: {m_oos['net_profit']:>9.2f}, PF: {m_oos['profit_factor']:.2f}, WR: {m_oos['win_rate']:.1f}%, DD: {m_oos['max_dd_pct']:.1f}%")

    df_bt_metrics = pd.DataFrame(bt_metrics_list)
    cols_order = ['Timeframe', 'Threshold', 'Set', 'trades', 'net_profit', 'net_profit_pct', 'profit_factor', 'win_rate', 'max_dd_pct', 'max_dd_usd', 'sharpe_ratio', 'ontester_score']
    df_bt_metrics = df_bt_metrics[cols_order]
    csv_bt_path = os.path.join(out_dir, f"backtest_metrics_{tf_name.lower()}.csv")
    df_bt_metrics.to_csv(csv_bt_path, index=False)

    # -------------------------------------------------------------------------
    # Etapa B: Evaluación bajo los 4 Perfiles de Riesgo si corresponde
    # -------------------------------------------------------------------------
    etapa_b_list = []
    # Test Etapa B if AUC OOS > 0.55 AND PF OOS approaches/exceeds 1.0, or run for comprehensive reporting
    print(f"\n--- Etapa B: Evaluando Modelo bajo los 4 Perfiles de Riesgo ({tf_name}) ---")
    profiles = [
        (0, "MANUAL"),
        (1, "CONSERVADOR"),
        (2, "BALANCEADO"),
        (3, "AGRESIVO")
    ]
    chosen_th = 0.53

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
            'Timeframe': tf_name,
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
    csv_etapa_b_path = os.path.join(out_dir, f"etapa_b_profiles_{tf_name.lower()}.csv")
    df_etapa_b.to_csv(csv_etapa_b_path, index=False)

    return {
        'timeframe': tf_name,
        'bars_is': len(df_is),
        'bars_oos': len(df_oos),
        'auc_is': is_auc,
        'auc_oos': oos_auc,
        'best_c': best_c,
        'ic_auc': df_ic_auc,
        'coefs': df_coef,
        'bt_metrics': df_bt_metrics,
        'etapa_b': df_etapa_b
    }


def main():
    parquet_path = "data/XAUUSD_M5_2019_2024.parquet"
    if not os.path.exists(parquet_path):
        raise FileNotFoundError(f"Data file not found at {parquet_path}. Run scripts/download_data.py first.")

    out_dir = "backtests/ciclo5_higher_timeframes"
    os.makedirs(out_dir, exist_ok=True)

    print("=== Ciclo 5: Diagnóstico y Modelo Ajustado en Temporalidades Mayores (H1 y H4) ===")
    print("Cargando dataset M5...")
    df_m5 = pd.read_parquet(parquet_path)

    # Run pipeline for H1: primary timeframe H1 ('1h'), HTF reference D1 ('1D'), horizons K=1, 3, 6 H1 bars
    res_h1 = run_pipeline_for_timeframe(df_m5, resample_rule='1h', tf_name='H1', htf_rule='1D', horizons=[1, 3, 6], out_dir=out_dir)

    # Run pipeline for H4: primary timeframe H4 ('4h'), HTF reference D1 ('1D'), horizons K=1, 3, 6 H4 bars
    res_h4 = run_pipeline_for_timeframe(df_m5, resample_rule='4h', tf_name='H4', htf_rule='1D', horizons=[1, 3, 6], out_dir=out_dir)

    print("\n=========================================================================")
    print(" RESUMEN Y COMPARACIÓN M5 vs H1 vs H4")
    print("=========================================================================")
    print(f"M5 (Ciclo 4): AUC IS = 0.52968 | AUC OOS = 0.51601")
    print(f"H1 (Ciclo 5): AUC IS = {res_h1['auc_is']:.5f} | AUC OOS = {res_h1['auc_oos']:.5f}")
    print(f"H4 (Ciclo 5): AUC IS = {res_h4['auc_is']:.5f} | AUC OOS = {res_h4['auc_oos']:.5f}")
    print("=========================================================================")

if __name__ == "__main__":
    main()
