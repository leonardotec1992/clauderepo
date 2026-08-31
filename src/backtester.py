import numpy as np
import pandas as pd
import math

def calculate_indicators(df_m5):
    """
    Computes all technical indicators required by BayesianGold_XAU_Panel on M5 and H1.
    - M5: RSI(14), CCI(14), ATR(14), EMA(100)
    - H1 (resampled from M5): ADX(14), EMA_Fast(50), EMA_Slow(200)
    """
    df = df_m5.copy()

    # 1. M5 RSI (14, Close)
    delta = df['Close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    # Use standard Wilder's EMA for RSI or rolling mean approximation
    # MQL5 iRSI uses Exponential smoothing for RSI:
    gain_ema = delta.clip(lower=0).ewm(alpha=1/14, adjust=False).mean()
    loss_ema = (-delta.clip(upper=0)).ewm(alpha=1/14, adjust=False).mean()
    rs = gain_ema / loss_ema.replace(0, np.nan)
    df['RSI'] = 100 - (100 / (1 + rs))
    df['RSI'] = df['RSI'].fillna(50.0)

    # 2. M5 CCI (14, Typical Price)
    tp = (df['High'] + df['Low'] + df['Close']) / 3.0
    tp_sma = tp.rolling(window=14).mean()
    # Mean absolute deviation
    mad = tp.rolling(window=14).apply(lambda x: np.mean(np.abs(x - np.mean(x))), raw=True)
    df['CCI'] = (tp - tp_sma) / (0.015 * mad)
    df['CCI'] = df['CCI'].fillna(0.0)

    # 3. M5 ATR (14) - Wilder's RMA
    tr1 = df['High'] - df['Low']
    tr2 = (df['High'] - df['Close'].shift(1)).abs()
    tr3 = (df['Low'] - df['Close'].shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['ATR'] = tr.ewm(alpha=1/14, adjust=False).mean()

    # 4. M5 EMA (100, Close)
    df['EMA_100'] = df['Close'].ewm(span=100, adjust=False).mean()

    # 5. H1 indicators (Resample M5 to H1)
    # Note: In MT5, H1 indicators on closed H1 bar (shift=1) are calculated from completed H1 bars.
    df_h1 = df.resample('1h').agg({
        'Open': 'first',
        'High': 'max',
        'Low': 'min',
        'Close': 'last'
    }).dropna()

    df_h1['EMA_Fast'] = df_h1['Close'].ewm(span=50, adjust=False).mean()
    df_h1['EMA_Slow'] = df_h1['Close'].ewm(span=200, adjust=False).mean()

    # ADX(14) on H1
    h1_high = df_h1['High']
    h1_low = df_h1['Low']
    h1_close = df_h1['Close']

    up_move = h1_high - h1_high.shift(1)
    down_move = h1_low.shift(1) - h1_low

    plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
    minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)

    tr1_h1 = h1_high - h1_low
    tr2_h1 = (h1_high - h1_close.shift(1)).abs()
    tr3_h1 = (h1_low - h1_close.shift(1)).abs()
    tr_h1 = pd.concat([tr1_h1, tr2_h1, tr3_h1], axis=1).max(axis=1)

    atr_h1 = tr_h1.ewm(alpha=1/14, adjust=False).mean()
    plus_di = 100 * (pd.Series(plus_dm, index=df_h1.index).ewm(alpha=1/14, adjust=False).mean() / atr_h1)
    minus_di = 100 * (pd.Series(minus_dm, index=df_h1.index).ewm(alpha=1/14, adjust=False).mean() / atr_h1)

    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan)
    df_h1['ADX'] = dx.ewm(alpha=1/14, adjust=False).mean().fillna(0.0)

    # Forward fill H1 indicators onto M5 dataframe
    # To prevent lookahead, shift H1 values by 1 H1 bar before merging!
    df_h1_shifted = df_h1[['EMA_Fast', 'EMA_Slow', 'ADX']].shift(1)
    df = pd.merge_asof(df, df_h1_shifted, left_index=True, right_index=True, direction='backward')

    return df


def clip(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)

def logit(p):
    p = clip(p, 1e-6, 1.0 - 1e-6)
    return math.log(p / (1.0 - p))

def sigmoid(x):
    return 1.0 / (1.0 + math.exp(-x))

def compute_posterior_up(rsi_now, rsi_prev, cci, atr, close_prev, open_prev, ema_prev, params):
    if atr <= 0:
        atr = 0.01  # point guard

    sRSI   = clip((50.0 - rsi_now) / 50.0, -1.0, 1.0)
    sCCI   = clip((-cci) / 150.0, -1.0, 1.0)
    sSlope = clip((rsi_now - rsi_prev) / 25.0, -1.0, 1.0)
    sRet   = clip((close_prev - open_prev) / atr, -1.0, 1.0)
    sTrend = clip((close_prev - ema_prev) / atr, -1.0, 1.0)

    log_odds = logit(params['InpPriorUp']) + \
               params['InpW_RSI'] * sRSI + \
               params['InpW_CCI'] * sCCI + \
               params['InpW_Slope'] * sSlope + \
               params['InpW_Return'] * sRet + \
               params['InpW_Trend'] * sTrend

    return sigmoid(log_odds)


class Position:
    def __init__(self, ticket, pos_type, open_price, open_time, lot, sl, tp, magic=20260001):
        self.ticket = ticket
        self.type = pos_type  # 'BUY' or 'SELL'
        self.open_price = open_price
        self.open_time = open_time
        self.lot = lot
        self.sl = sl
        self.tp = tp
        self.magic = magic

class Backtester:
    def __init__(self, df, initial_balance=10000.0, params=None):
        self.df = df
        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.equity = initial_balance

        # Default EA Parameters (Matching MQL5 defaults)
        self.params = {
            'StartingLots': 0.03,
            'TakeProfit': 0.0,
            'Max_SL_Puntos': 1000.0,
            'Layer_Multiplier': 10,  # LM_10 = x1.0
            'LayerStepATR': 1.0,
            'LayerLotFactor': 1.0,
            'AutoCompound': False,
            'Usar_Shield': True,
            'Shield_Pct': 15.0,
            'Usar_Objetivo': True,
            'Objetivo_Diario': 20.0,
            'Usar_Breakeven': True,
            'BE_Activacion': 80.0,
            'Usar_Trailing': False,
            'Trailing_Activar': 30.0,
            'Trailing_Dist': 75.0,
            'Operar_24H': False,
            'Sesion_NuevaYork': True, 'NY_Hora_Inicio': 8, 'NY_Hora_Cierre': 11,
            'Sesion_Asia': True,     'Asia_Hora_Inicio': 22, 'Asia_Hora_Cierre': 2,
            'Sesion_Londres': True,  'Londres_Hora_Inicio': 2, 'Londres_Hora_Cierre': 11,
            'Usar_Spread_Max': True, 'Spread_Max': 30.0,
            'Usar_Margen': True, 'Margen_Minimo': 20.0,
            'Usar_EMA_Filter': True, 'EMA_Sep_Extrema': 0.3,
            'Usar_Filtro_ADX': True, 'ADX_Minimo': 25.0,
            'Usar_Compuesto': True,  'Compuesto_Pct': 1.0,
            'Perfil_Riesgo': 0,      # MANUAL
            'InpPriorUp': 0.50,
            'InpThreshold': 0.62,
            'InpW_RSI': 1.10,
            'InpW_CCI': 0.70,
            'InpW_Slope': 0.60,
            'InpW_Return': 0.50,
            'InpW_Trend': 0.40,
            'InpUseRSIConfirm': True,
            'InpRSI_LongMax': 55.0,
            'InpRSI_ShortMin': 45.0,
            'InpUseAntiExtremos': True,
            'InpUseVolGate': True,
            'InpATRMinPts': 80.0,
            'InpATRMaxPts': 900.0,
            'InpRiskMode': 0,        # RISK_FIXED_LOT = 0
            'InpRiskPercent': 0.5,
            'InpSL_ATR': 2.0,
            'InpTP_R': 1.5,
            'InpBE_OffsetPts': 20.0,
            'InpTrail_MinATR': 0.3,
            'InpUseLayers': False,
            'InpMaxLayers': 3,
            'SpreadPts': 30.0,      # 30 points = $0.30/oz
            'CommissionPerLot': 3.50 # $3.50 per lot round turn
        }
        if params:
            self.params.update(params)

        self.apply_profile()

        self.positions = []
        self.closed_trades = []
        self.equity_curve = []
        self.ticket_counter = 1

        # Daily tracking global variables
        self.g_dayStamp = -1
        self.g_dayStartBal = initial_balance
        self.g_shieldTripped = False
        self.g_objTripped = False

    def apply_profile(self):
        p = self.params
        self.g_profile = p.get('Perfil_Riesgo', 0)

        # Defaults for MANUAL (0)
        self.g_shieldMax = p.get('Shield_Pct', 15.0)
        self.g_riskPct = p.get('InpRiskPercent', 0.5)
        self.g_maxLayers = p.get('InpMaxLayers', 3)
        self.g_useLayers = p.get('InpUseLayers', False)
        self.g_usePercent = (p.get('InpRiskMode', 0) == 1)
        self.g_objetivoPct = 0.0
        self.g_bePct = p.get('BE_Activacion', 80.0)

        # Profiles matching ApplyProfile() in BayesianGold_XAU_Panel.mq5
        if self.g_profile == 1:    # CONSERVADOR
            self.g_shieldMax = 3.0
            self.g_riskPct = 0.5
            self.g_useLayers = True
            self.g_maxLayers = 6
            self.g_usePercent = True
            self.g_objetivoPct = 2.0
            self.g_bePct = 70.0
        elif self.g_profile == 2:  # BALANCEADO
            self.g_shieldMax = 4.0
            self.g_riskPct = 1.0
            self.g_useLayers = True
            self.g_maxLayers = 10
            self.g_usePercent = True
            self.g_objetivoPct = 3.0
            self.g_bePct = 80.0
        elif self.g_profile == 3:  # AGRESIVO
            self.g_shieldMax = 6.0
            self.g_riskPct = 1.8
            self.g_useLayers = True
            self.g_maxLayers = 15
            self.g_usePercent = True
            self.g_objetivoPct = 5.0
            self.g_bePct = 80.0

    def in_session(self, dt):
        if self.params['Operar_24H']:
            return True
        h = dt.hour
        # Check session windows
        def en_ventana(h, ini, fin):
            if ini == fin: return False
            if ini < fin: return ini <= h < fin
            return h >= ini or h < fin

        p = self.params
        if p['Sesion_NuevaYork'] and en_ventana(h, p['NY_Hora_Inicio'], p['NY_Hora_Cierre']):
            return True
        if p['Sesion_Londres'] and en_ventana(h, p['Londres_Hora_Inicio'], p['Londres_Hora_Cierre']):
            return True
        if p['Sesion_Asia'] and en_ventana(h, p['Asia_Hora_Inicio'], p['Asia_Hora_Cierre']):
            return True
        return False

    def ema_allows(self, is_long, price, ema_f, ema_s):
        if not self.params['Usar_EMA_Filter']:
            return True
        if pd.isna(ema_f) or pd.isna(ema_s) or ema_f <= 0 or ema_s <= 0 or price <= 0:
            return True
        sep_pct = (ema_f - ema_s) / price * 100.0
        if abs(sep_pct) < self.params['EMA_Sep_Extrema']:
            return True
        return sep_pct > 0 if is_long else sep_pct < 0

    def adx_allows(self, adx):
        if not self.params['Usar_Filtro_ADX']:
            return True
        if pd.isna(adx) or adx <= 0:
            return True
        return adx >= self.params['ADX_Minimo']

    def calc_lot(self, balance, sl_dist_price=0.0):
        p = self.params
        if not self.g_usePercent:
            lot = p['StartingLots']
            if p.get('AutoCompound', False) or p.get('Usar_Compuesto', True):
                steps = math.floor(balance / 100.0)
                if steps < 1: steps = 1
                lot = p['StartingLots'] * steps * p.get('Compuesto_Pct', 1.0)
            lot = math.floor(lot / 0.01) * 0.01
            if lot < 0.01: lot = 0.01
            if lot > 100.0: lot = 100.0
            return round(lot, 2)
        else:
            risk = balance * self.g_riskPct / 100.0
            loss_per_lot = sl_dist_price * 100.0  # $100 USD per $1.00 move per 1.0 lot in XAUUSD
            if loss_per_lot <= 0:
                lot = p['StartingLots']
            else:
                lot = risk / loss_per_lot
            lot = math.floor(lot / 0.01) * 0.01
            if lot < 0.01: lot = 0.01
            if lot > 100.0: lot = 100.0
            return round(lot, 2)

    def count_positions(self):
        return len(self.positions)

    def net_direction(self):
        if not self.positions:
            return 0
        return 1 if self.positions[0].type == 'BUY' else -1

    def last_entry_price(self, dir_val):
        if not self.positions:
            return 0.0
        if dir_val > 0:
            return min(pos.open_price for pos in self.positions)
        else:
            return max(pos.open_price for pos in self.positions)

    def try_add_layer(self, p_up, ask, bid, atr_now, dt):
        n_pos = self.count_positions()
        if n_pos >= self.g_maxLayers:
            return
        if atr_now <= 0:
            return
        dir_val = self.net_direction()
        if dir_val == 0:
            return

        last_entry = self.last_entry_price(dir_val)
        step = self.params.get('LayerStepATR', 1.0) * atr_now

        add_long = (dir_val > 0 and p_up >= self.params['InpThreshold'] and (last_entry - ask) >= step)
        add_short = (dir_val < 0 and p_up <= (1.0 - self.params['InpThreshold']) and (bid - last_entry) >= step)

        if not (add_long or add_short):
            return

        sl_dist = atr_now * self.params['InpSL_ATR']
        mult_val = self.params.get('Layer_Multiplier', self.params.get('LayerMultiplier', 10))
        mult = float(mult_val) / 10.0
        n_capa = n_pos  # 2nd position index is 1

        base_lot = self.calc_lot(self.balance, sl_dist)
        layer_lot_factor = self.params.get('LayerLotFactor', 1.0)
        lot = base_lot * layer_lot_factor * (mult ** n_capa)

        lot = math.floor(lot / 0.01) * 0.01
        if lot < 0.01: lot = 0.01
        if lot > 100.0: lot = 100.0
        lot = round(lot, 2)

        if lot <= 0:
            return

        point = 0.01
        tp_dist = self.params['TakeProfit'] * point if self.params['TakeProfit'] > 0 else sl_dist * self.params['InpTP_R']

        if add_long:
            sl = ask - sl_dist
            tp = ask + tp_dist
            pos = Position(self.ticket_counter, 'BUY', ask, dt, lot, round(sl, 2), round(tp, 2))
            self.ticket_counter += 1
            self.positions.append(pos)
        elif add_short:
            sl = bid + sl_dist
            tp = bid - tp_dist
            pos = Position(self.ticket_counter, 'SELL', bid, dt, lot, round(sl, 2), round(tp, 2))
            self.ticket_counter += 1
            self.positions.append(pos)

    def run(self):
        point = 0.01 # 1 point in XAUUSD = 0.01 USD (100 points = $1.00)
        spread_val = self.params['SpreadPts'] * point

        # Reset daily counters
        self.g_dayStamp = -1
        self.g_dayStartBal = self.initial_balance
        self.g_shieldTripped = False
        self.g_objTripped = False

        dates = self.df.index
        opens = self.df['Open'].values
        highs = self.df['High'].values
        lows = self.df['Low'].values
        closes = self.df['Close'].values
        rsis = self.df['RSI'].values
        ccis = self.df['CCI'].values
        atrs = self.df['ATR'].values
        ema100s = self.df['EMA_100'].values
        ema_fasts = self.df['EMA_Fast'].values
        ema_slows = self.df['EMA_Slow'].values
        adxs = self.df['ADX'].values

        n_bars = len(self.df)

        for i in range(1, n_bars):
            dt = dates[i]
            open_p = opens[i]
            high_p = highs[i]
            low_p = lows[i]
            close_p = closes[i]

            # Current bid/ask
            bid = open_p
            ask = open_p + spread_val

            # Daily reset check
            day_of_year = dt.dayofyear
            if day_of_year != self.g_dayStamp:
                self.g_dayStamp = day_of_year
                # Realized today balance
                self.g_dayStartBal = self.balance
                self.g_shieldTripped = False
                self.g_objTripped = False

            # Check Margin Call / Stop-out / Bankrupt before processing bar
            if self.balance <= 0 or self.equity <= 0:
                if self.positions:
                    self.close_all_positions(bid, ask, dt, "Stop Out")
                self.balance = max(0.0, self.balance)
                self.equity = max(0.0, self.equity)
                self.equity_curve.append({'Date': dt, 'Balance': self.balance, 'Equity': self.equity})
                break

            # Calculate floating PnL
            floating_pnl = 0.0
            for pos in self.positions:
                if pos.type == 'BUY':
                    floating_pnl += (bid - pos.open_price) * 100.0 * pos.lot
                else:
                    floating_pnl += (pos.open_price - ask) * 100.0 * pos.lot

            ganancia_hoy = (self.balance - self.g_dayStartBal) + floating_pnl
            day_start_bal = self.g_dayStartBal if self.g_dayStartBal > 0 else self.balance

            daily_dd_pct = max(0.0, -ganancia_hoy / day_start_bal * 100.0)
            daily_gain_pct = (ganancia_hoy / day_start_bal * 100.0) if day_start_bal > 0 else 0.0

            # Update Shield & Daily Goal
            if self.params['Usar_Shield'] and not self.g_shieldTripped and daily_dd_pct >= self.g_shieldMax:
                self.g_shieldTripped = True
                # Close all
                self.close_all_positions(bid, ask, dt, "Shield Tripped")
                floating_pnl = 0.0

            meta_pct = self.params['Objetivo_Diario'] if self.g_profile == 0 else self.g_objetivoPct
            if self.params['Usar_Objetivo'] and not self.g_objTripped and meta_pct > 0 and daily_gain_pct >= meta_pct:
                self.g_objTripped = True
                self.close_all_positions(bid, ask, dt, "Daily Goal Met")
                floating_pnl = 0.0

            # Manage existing positions (SL / TP / BE / Trailing intra-bar)
            atr_now = atrs[i-1] if not pd.isna(atrs[i-1]) else 1.0
            self.manage_positions_bar(high_p, low_p, bid, ask, dt, atr_now, point)

            # Recalculate floating PnL after managing positions
            floating_pnl = 0.0
            for pos in self.positions:
                if pos.type == 'BUY':
                    floating_pnl += (bid - pos.open_price) * 100.0 * pos.lot
                else:
                    floating_pnl += (pos.open_price - ask) * 100.0 * pos.lot

            # Update Equity
            current_equity = self.balance + floating_pnl
            self.equity = current_equity

            # Check Margin Call / Stop-out after position management
            if self.balance <= 0 or current_equity <= 0:
                if self.positions:
                    self.close_all_positions(bid, ask, dt, "Stop Out")
                self.balance = max(0.0, self.balance)
                self.equity = max(0.0, self.equity)
                self.equity_curve.append({'Date': dt, 'Balance': self.balance, 'Equity': self.equity})
                break

            self.equity_curve.append({'Date': dt, 'Balance': self.balance, 'Equity': current_equity})

            # Gate checks for new signals
            if self.params['Usar_Shield'] and self.g_shieldTripped:
                continue
            if self.params['Usar_Objetivo'] and self.g_objTripped:
                continue
            if not self.in_session(dt):
                continue

            atr_pts = atr_now / point
            if self.params['InpUseVolGate'] and (atr_pts < self.params['InpATRMinPts'] or atr_pts > self.params['InpATRMaxPts']):
                continue

            # Compute Posterior Up probability (using completed bar i-1)
            rsi_now = rsis[i-1]
            rsi_prev = rsis[i-2] if i >= 2 else 50.0
            cci_now = ccis[i-1]
            close_prev = closes[i-1]
            open_prev = opens[i-1]
            ema_prev = ema100s[i-1]

            p_up = compute_posterior_up(rsi_now, rsi_prev, cci_now, atr_now, close_prev, open_prev, ema_prev, self.params)

            go_long = (p_up >= self.params['InpThreshold'])
            go_short = (p_up <= 1.0 - self.params['InpThreshold'])

            if not self.ema_allows(True, bid, ema_fasts[i], ema_slows[i]):
                go_long = False
            if not self.ema_allows(False, bid, ema_fasts[i], ema_slows[i]):
                go_short = False

            if self.params['InpUseRSIConfirm']:
                if rsi_now > self.params['InpRSI_LongMax']: go_long = False
                if rsi_now < self.params['InpRSI_ShortMin']: go_short = False

            if self.params['InpUseAntiExtremos']:
                if rsi_now > 75.0 and cci_now > 150.0: go_long = False
                if rsi_now < 25.0 and cci_now < -150.0: go_short = False

            n_pos = len(self.positions)
            if n_pos > 0 and not self.g_useLayers:
                continue
            if not self.adx_allows(adxs[i]):
                continue

            # Spread filter
            if self.params['Usar_Spread_Max'] and self.params['SpreadPts'] > self.params['Spread_Max']:
                continue

            # Margin check filter
            if self.params['Usar_Margen']:
                # Basic check: balance must be positive to open position
                if self.balance <= 0 or self.equity <= 0:
                    continue

            # Entry Logic
            if n_pos == 0:
                sl_dist = atr_now * self.params['InpSL_ATR']
                if self.params['Max_SL_Puntos'] > 0 and (sl_dist / point) > self.params['Max_SL_Puntos']:
                    continue

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

        # Close remaining positions at end of backtest if still open and account active
        if self.df.empty:
            return
        last_dt = dates[-1]
        last_close = closes[-1]
        if self.positions:
            self.close_all_positions(last_close, last_close + spread_val, last_dt, "End of Backtest")

    def manage_positions_bar(self, high_p, low_p, bid, ask, dt, atr, point):
        remaining = []
        for pos in self.positions:
            closed = False
            if pos.type == 'BUY':
                # Check SL/TP using High and Low of bar
                # Price moves: Bid reaches low_p or high_p
                # Low checks SL, High checks TP
                hit_sl = low_p <= pos.sl if pos.sl > 0 else False
                hit_tp = high_p >= pos.tp if pos.tp > 0 else False

                if hit_sl and hit_tp:
                    # Whichever is closer to open_price usually hits first, or conservative SL
                    exit_price = pos.sl
                    closed = True
                    reason = "SL (bar worst)"
                elif hit_sl:
                    exit_price = pos.sl
                    closed = True
                    reason = "SL"
                elif hit_tp:
                    exit_price = pos.tp
                    closed = True
                    reason = "TP"
                else:
                    # Check Break-even and Trailing
                    gain = bid - pos.open_price
                    new_sl = pos.sl
                    if self.params['Usar_Breakeven']:
                        trig = (bid >= pos.open_price + (pos.tp - pos.open_price) * self.g_bePct / 100.0) if pos.tp > pos.open_price else (gain >= atr)
                        if trig:
                            be = pos.open_price + self.params['InpBE_OffsetPts'] * point
                            if be > new_sl: new_sl = be

                    if self.params['Usar_Trailing']:
                        trail_on = (bid >= pos.open_price + (pos.tp - pos.open_price) * self.params['Trailing_Activar'] / 100.0) if pos.tp > pos.open_price else (gain >= self.params['InpTrail_MinATR'] * atr)
                        if trail_on:
                            tr = pos.open_price + gain * self.params['Trailing_Dist'] / 100.0
                            if tr > new_sl: new_sl = tr
                    pos.sl = round(new_sl, 2)

            elif pos.type == 'SELL':
                # For sell, Ask price hits SL/TP. High ask = high_p + spread, Low ask = low_p + spread
                high_ask = high_p + self.params['SpreadPts'] * point
                low_ask = low_p + self.params['SpreadPts'] * point

                hit_sl = high_ask >= pos.sl if pos.sl > 0 else False
                hit_tp = low_ask <= pos.tp if pos.tp > 0 else False

                if hit_sl and hit_tp:
                    exit_price = pos.sl
                    closed = True
                    reason = "SL (bar worst)"
                elif hit_sl:
                    exit_price = pos.sl
                    closed = True
                    reason = "SL"
                elif hit_tp:
                    exit_price = pos.tp
                    closed = True
                    reason = "TP"
                else:
                    gain = pos.open_price - ask
                    new_sl = pos.sl
                    if self.params['Usar_Breakeven']:
                        trig = (ask <= pos.open_price - (pos.open_price - pos.tp) * self.g_bePct / 100.0) if (pos.tp < pos.open_price and pos.tp > 0) else (gain >= atr)
                        if trig:
                            be = pos.open_price - self.params['InpBE_OffsetPts'] * point
                            if pos.sl == 0 or be < new_sl: new_sl = be

                    if self.params['Usar_Trailing']:
                        trail_on = (ask <= pos.open_price - (pos.open_price - pos.tp) * self.params['Trailing_Activar'] / 100.0) if (pos.tp < pos.open_price and pos.tp > 0) else (gain >= self.params['InpTrail_MinATR'] * atr)
                        if trail_on:
                            tr = pos.open_price - gain * self.params['Trailing_Dist'] / 100.0
                            if pos.sl == 0 or tr < new_sl: new_sl = tr
                    pos.sl = round(new_sl, 2)

            if closed:
                pnl = (exit_price - pos.open_price) * 100.0 * pos.lot if pos.type == 'BUY' else (pos.open_price - exit_price) * 100.0 * pos.lot
                comm = pos.lot * self.params['CommissionPerLot']
                net_pnl = pnl - comm
                self.balance += net_pnl
                self.closed_trades.append({
                    'Ticket': pos.ticket, 'Type': pos.type, 'OpenTime': pos.open_time,
                    'CloseTime': dt, 'OpenPrice': pos.open_price, 'ClosePrice': exit_price,
                    'Lot': pos.lot, 'PnL': pnl, 'Commission': comm, 'NetPnL': net_pnl, 'Reason': reason
                })
            else:
                remaining.append(pos)

        self.positions = remaining

    def close_all_positions(self, bid, ask, dt, reason):
        for pos in self.positions:
            exit_price = bid if pos.type == 'BUY' else ask
            pnl = (exit_price - pos.open_price) * 100.0 * pos.lot if pos.type == 'BUY' else (pos.open_price - exit_price) * 100.0 * pos.lot
            comm = pos.lot * self.params['CommissionPerLot']
            net_pnl = pnl - comm
            self.balance += net_pnl
            self.closed_trades.append({
                'Ticket': pos.ticket, 'Type': pos.type, 'OpenTime': pos.open_time,
                'CloseTime': dt, 'OpenPrice': pos.open_price, 'ClosePrice': exit_price,
                'Lot': pos.lot, 'PnL': pnl, 'Commission': comm, 'NetPnL': net_pnl, 'Reason': reason
            })
        self.positions = []


def calculate_metrics(trades_list, equity_df, initial_balance=10000.0):
    if not trades_list:
        return {
            'trades': 0, 'net_profit': 0.0, 'net_profit_pct': 0.0, 'profit_factor': 0.0,
            'win_rate': 0.0, 'max_dd_pct': 0.0, 'max_dd_usd': 0.0, 'sharpe_ratio': 0.0,
            'ontester_score': 0.0
        }

    df_trades = pd.DataFrame(trades_list)
    net_profit = df_trades['NetPnL'].sum()
    net_profit_pct = (net_profit / initial_balance) * 100.0
    gross_profit = df_trades[df_trades['NetPnL'] > 0]['NetPnL'].sum()
    gross_loss = abs(df_trades[df_trades['NetPnL'] < 0]['NetPnL'].sum())

    profit_factor = gross_profit / gross_loss if gross_loss > 0 else (999.0 if gross_profit > 0 else 0.0)
    win_rate = (len(df_trades[df_trades['NetPnL'] > 0]) / len(df_trades)) * 100.0

    # Drawdown from equity curve
    equity = equity_df['Equity']
    peak = equity.cummax()
    dd_usd_series = peak - equity
    max_dd_usd = dd_usd_series.max()
    dd_pct_series = (peak - equity) / peak * 100.0
    max_dd_pct = dd_pct_series.max()

    # Daily Sharpe Ratio
    equity_df['DailyReturn'] = equity_df['Equity'].pct_change()
    daily_returns = equity_df['DailyReturn'].dropna()
    std = daily_returns.std()
    sharpe_ratio = (daily_returns.mean() / std * np.sqrt(252)) if std > 0 else 0.0

    trades = len(df_trades)

    # OnTester Score exact formula
    if trades < 40 or net_profit <= 0 or profit_factor < 1.15 or max_dd_pct > 25.0:
        ontester_score = 0.0
    else:
        ontester_score = profit_factor * np.sqrt(trades) / (1.0 + max_dd_pct / 10.0)
        ontester_score *= (1.0 + max(sharpe_ratio, 0.0) * 0.1)

    return {
        'trades': trades,
        'net_profit': round(net_profit, 2),
        'net_profit_pct': round(net_profit_pct, 2),
        'profit_factor': round(profit_factor, 2),
        'win_rate': round(win_rate, 2),
        'max_dd_pct': round(max_dd_pct, 2),
        'max_dd_usd': round(max_dd_usd, 2),
        'sharpe_ratio': round(sharpe_ratio, 2),
        'ontester_score': round(ontester_score, 2)
    }
