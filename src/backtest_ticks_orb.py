"""
Tick-by-tick backtester for Strategy 2: ORB (Opening Range Breakout) on M5 timeframe.

Data source: Dukascopy XAUUSD tick files (.csv.gz) in datos/ticks_dukascopy/
Execution rules:
- Opening range starts at 08:00 (UTC/local timestamp).
- Tested window durations: 30 min, 60 min, 90 min.
- Signal evaluated on M5 candle completion after the opening range closes.
- BUY if M5 close > range_high, SELL if M5 close < range_low.
- Constraint: Maximum 1 operation per day per ORB window.
- BUY fills at Ask, SELL fills at Bid on the first tick of the next M5 candle.
- SL evaluated tick-by-tick at 2.0x ATR(14 in M5).
- TP evaluated tick-by-tick at 4.0x ATR(14 in M5) (2.0x SL distance).
- Position size: 1 fixed unit. Single position at a time.
- Commission = 0, Slippage = 0.
"""

import os
import glob
import datetime
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from typing import Dict, List, Any

from src.indicators import compute_atr


def build_m5_candles_from_ticks(tick_files: List[str]) -> pd.DataFrame:
    """
    Pass 1: Reads tick files in chunks, aggregates ticks into M5 OHLC candles,
    and computes ATR(14) on M5 candles.
    """
    m5_bars_list = []

    for fpath in tick_files:
        print(f"Reading ticks for M5 aggregation: {os.path.basename(fpath)}...")
        chunks = pd.read_csv(fpath, chunksize=500000)
        for chunk in chunks:
            chunk['timestamp'] = pd.to_datetime(chunk['timestamp'])
            chunk.set_index('timestamp', inplace=True)
            resampled = chunk['bid'].resample('5min').agg(
                open='first',
                high='max',
                low='min',
                close='last'
            ).dropna()
            if not resampled.empty:
                m5_bars_list.append(resampled)

    if not m5_bars_list:
        raise ValueError("No tick data loaded!")

    full_m5 = pd.concat(m5_bars_list)
    full_m5 = full_m5.groupby(full_m5.index).agg({
        'open': 'first',
        'high': 'max',
        'low': 'min',
        'close': 'last'
    }).sort_index()

    full_m5['atr14'] = compute_atr(full_m5, 14)
    return full_m5


def compute_orb_daily_ranges(m5_df: pd.DataFrame, range_minutes: int, open_time_str: str = "08:00") -> pd.DataFrame:
    """
    Computes daily ORB range_high and range_low for a given window duration starting at open_time_str.
    Returns copy of m5_df with columns: range_high, range_low, orb_active, signal.
    """
    df = m5_df.copy()
    df['range_high'] = np.nan
    df['range_low'] = np.nan
    df['orb_active'] = False
    df['signal'] = 0

    open_h, open_m = map(int, open_time_str.split(':'))
    start_time_obj = datetime.time(open_h, open_m)

    end_dt = datetime.datetime(2000, 1, 1, open_h, open_m) + datetime.timedelta(minutes=range_minutes)
    end_time_obj = end_dt.time()

    df['_date'] = df.index.date

    for date_val, group in df.groupby('_date'):
        times = group.index.time
        range_mask = (times >= start_time_obj) & (times < end_time_obj)
        after_mask = (times >= end_time_obj)

        range_candles = group[range_mask]
        if not range_candles.empty:
            r_high = range_candles['high'].max()
            r_low = range_candles['low'].min()

            df.loc[group.index, 'range_high'] = r_high
            df.loc[group.index, 'range_low'] = r_low
            df.loc[group[after_mask].index, 'orb_active'] = True

    active_mask = df['orb_active']
    buy_cond = active_mask & (df['close'] > df['range_high'])
    sell_cond = active_mask & (df['close'] < df['range_low'])

    df.loc[buy_cond, 'signal'] = 1
    df.loc[sell_cond, 'signal'] = -1

    df.drop(columns=['_date'], inplace=True)
    return df


def run_orb_tick_backtest(tick_files: List[str], m5_df: pd.DataFrame, range_minutes: int, initial_capital: float = 10000.0) -> Dict[str, Any]:
    """
    Pass 2: Fast vectorized tick-by-tick backtester for ORB.
    """
    orb_m5 = compute_orb_daily_ranges(m5_df, range_minutes)

    # Key: candle boundary timestamp when trade can execute -> dict(signal, atr14)
    m5_signals = {}
    for idx, row in orb_m5.iterrows():
        next_m5 = idx + pd.Timedelta(minutes=5)
        sig = int(row['signal'])
        atr = float(row['atr14'])
        if sig != 0 and not np.isnan(atr) and atr > 0:
            m5_signals[next_m5] = {'signal': sig, 'atr14': atr}

    trades = []
    equity = initial_capital
    position = None
    seen_m5_bars = set()
    traded_dates = set()
    equity_curve = []

    strat_label = f"ORB ({range_minutes}m) M5 Ticks"

    for fpath in tick_files:
        print(f"Streaming ticks for ORB {range_minutes}m simulation: {os.path.basename(fpath)}...")
        chunks = pd.read_csv(fpath, chunksize=500000)

        for chunk in chunks:
            chunk['timestamp'] = pd.to_datetime(chunk['timestamp'])
            chunk['m5'] = chunk['timestamp'].dt.floor('5min')

            timestamps = chunk['timestamp'].values
            bids = chunk['bid'].values
            asks = chunk['ask'].values
            m5s = chunk['m5'].values

            i = 0
            n = len(chunk)

            while i < n:
                ts = pd.Timestamp(timestamps[i])
                curr_m5 = pd.Timestamp(m5s[i])

                # Check if a position is currently open
                if position is not None:
                    p_type = position['type']
                    sl_p = position['sl']
                    tp_p = position['tp']

                    if p_type == 'BUY':
                        sl_hits = np.where(bids[i:] <= sl_p)[0]
                        tp_hits = np.where(bids[i:] >= tp_p)[0]
                    else:  # SELL
                        sl_hits = np.where(asks[i:] >= sl_p)[0]
                        tp_hits = np.where(asks[i:] <= sl_p)[0]

                    idx_sl = sl_hits[0] if len(sl_hits) > 0 else None
                    idx_tp = tp_hits[0] if len(tp_hits) > 0 else None

                    if idx_sl is None and idx_tp is None:
                        # Position stays open beyond current chunk
                        i = n
                    else:
                        if idx_sl is not None and (idx_tp is None or idx_sl <= idx_tp):
                            exit_idx = i + idx_sl
                            exit_price = sl_p
                            exit_reason = 'SL'
                        else:
                            exit_idx = i + idx_tp
                            exit_price = tp_p
                            exit_reason = 'TP'

                        exit_ts = pd.Timestamp(timestamps[exit_idx])
                        if p_type == 'BUY':
                            pnl = exit_price - position['entry_price']
                        else:
                            pnl = position['entry_price'] - exit_price

                        equity += pnl

                        trades.append({
                            'strategy': f"ORB ({range_minutes}m)",
                            'type': p_type,
                            'entry_time': position['entry_time'],
                            'entry_price': position['entry_price'],
                            'exit_time': exit_ts,
                            'exit_price': exit_price,
                            'sl': sl_p,
                            'tp': tp_p,
                            'pnl': pnl,
                            'return_pct': (pnl / initial_capital) * 100.0,
                            'exit_reason': exit_reason
                        })
                        position = None
                        equity_curve.append((exit_ts, equity))
                        i = exit_idx + 1

                else:
                    # No position open: check for new M5 bar signal arrival
                    if curr_m5 not in seen_m5_bars:
                        seen_m5_bars.add(curr_m5)
                        sig_info = m5_signals.get(curr_m5, None)
                        curr_date = ts.date()

                        if sig_info is not None and curr_date not in traded_dates:
                            sig = sig_info['signal']
                            atr_v = sig_info['atr14']
                            sl_dist = 2.0 * atr_v
                            tp_dist = 2.0 * sl_dist

                            bid = bids[i]
                            ask = asks[i]

                            if sig == 1:  # BUY
                                entry_price = ask
                                sl_p = entry_price - sl_dist
                                tp_p = entry_price + tp_dist
                                position = {
                                    'type': 'BUY',
                                    'entry_time': ts,
                                    'entry_price': entry_price,
                                    'sl': sl_p,
                                    'tp': tp_p
                                }
                                traded_dates.add(curr_date)
                            elif sig == -1:  # SELL
                                entry_price = bid
                                sl_p = entry_price + sl_dist
                                tp_p = entry_price - tp_dist
                                position = {
                                    'type': 'SELL',
                                    'entry_time': ts,
                                    'entry_price': entry_price,
                                    'sl': sl_p,
                                    'tp': tp_p
                                }
                                traded_dates.add(curr_date)

                    # Advance to next bar or end of chunk
                    if position is None:
                        next_bar_offsets = np.where(m5s[i:] != m5s[i])[0]
                        if len(next_bar_offsets) > 0:
                            i = i + next_bar_offsets[0]
                        else:
                            i = n

            # End of chunk snapshot for equity curve
            last_chunk_ts = pd.Timestamp(timestamps[-1])
            equity_curve.append((last_chunk_ts, equity))

    # Close open position at end if any
    if position is not None:
        p_type = position['type']
        last_exit = ask if p_type == 'SELL' else bid
        pnl = (last_exit - position['entry_price']) if p_type == 'BUY' else (position['entry_price'] - last_exit)
        equity += pnl
        trades.append({
            'strategy': f"ORB ({range_minutes}m)",
            'type': p_type,
            'entry_time': position['entry_time'],
            'entry_price': position['entry_price'],
            'exit_time': last_chunk_ts,
            'exit_price': last_exit,
            'sl': position['sl'],
            'tp': position['tp'],
            'pnl': pnl,
            'return_pct': (pnl / initial_capital) * 100.0,
            'exit_reason': 'END'
        })
        equity_curve.append((last_chunk_ts, equity))

    trades_df = pd.DataFrame(trades)
    eq_times, eq_values = zip(*equity_curve) if equity_curve else ([], [])
    equity_series = pd.Series(eq_values, index=pd.to_datetime(eq_times))

    metrics = compute_tick_metrics(trades_df, equity_series, initial_capital, strat_label)

    return {
        'metrics': metrics,
        'trades_df': trades_df,
        'equity_series': equity_series
    }


def compute_tick_metrics(trades_df: pd.DataFrame, equity_series: pd.Series, initial_capital: float, strat_name: str) -> Dict[str, Any]:
    if trades_df.empty:
        return {
            'Strategy': strat_name,
            'Trades': 0,
            'Net Profit ($)': 0.0,
            'Win Rate (%)': 0.0,
            'Profit Factor': 0.0,
            'Sharpe Ratio': 0.0,
            'Max Drawdown ($)': 0.0,
            'Max Drawdown (%)': 0.0,
            'Avg Win ($)': 0.0,
            'Avg Loss ($)': 0.0
        }

    n_trades = len(trades_df)
    net_profit = trades_df['pnl'].sum()

    wins = trades_df[trades_df['pnl'] > 0]['pnl']
    losses = trades_df[trades_df['pnl'] < 0]['pnl']

    n_wins = len(wins)
    win_rate = (n_wins / n_trades) * 100.0 if n_trades > 0 else 0.0

    gross_profit = wins.sum() if len(wins) > 0 else 0.0
    gross_loss = abs(losses.sum()) if len(losses) > 0 else 0.0

    if gross_loss == 0.0:
        profit_factor = float('inf') if gross_profit > 0 else 0.0
    else:
        profit_factor = gross_profit / gross_loss

    avg_win = wins.mean() if len(wins) > 0 else 0.0
    avg_loss = losses.mean() if len(losses) > 0 else 0.0

    peak = equity_series.cummax()
    drawdown = equity_series - peak
    drawdown_pct = (drawdown / peak) * 100.0

    max_dd_usd = abs(drawdown.min())
    max_dd_pct = abs(drawdown_pct.min())

    daily_eq = equity_series.groupby(equity_series.index.date).last()
    daily_returns = daily_eq.pct_change().dropna()

    if len(daily_returns) > 1 and daily_returns.std() > 0:
        sharpe = (daily_returns.mean() / daily_returns.std()) * np.sqrt(252)
    else:
        sharpe = 0.0

    return {
        'Strategy': strat_name,
        'Trades': n_trades,
        'Net Profit ($)': round(net_profit, 2),
        'Win Rate (%)': round(win_rate, 2),
        'Profit Factor': round(profit_factor, 2) if profit_factor != float('inf') else 999.0,
        'Sharpe Ratio': round(sharpe, 2),
        'Max Drawdown ($)': round(max_dd_usd, 2),
        'Max Drawdown (%)': round(max_dd_pct, 2),
        'Avg Win ($)': round(avg_win, 2),
        'Avg Loss ($)': round(avg_loss, 2)
    }


def main():
    tick_files = sorted(glob.glob('datos/ticks_dukascopy/xauusd_ticks_*.csv.gz'))
    if not tick_files:
        print("Error: No tick files found in datos/ticks_dukascopy/")
        return

    print(f"Found {len(tick_files)} tick files: {tick_files}")

    m5_df = build_m5_candles_from_ticks(tick_files)
    print(f"Aggregated M5 candles count: {len(m5_df)} | Date range: {m5_df.index.min()} to {m5_df.index.max()}")

    output_dir = 'resultados'
    os.makedirs(output_dir, exist_ok=True)

    summary_metrics = []

    for range_mins in [30, 60, 90]:
        print(f"\n--- Running ORB {range_mins}m Tick Backtest ---")
        res = run_orb_tick_backtest(tick_files, m5_df, range_mins)

        trades_csv_path = os.path.join(output_dir, f'trades_ORB_{range_mins}m_ticks.csv')
        res['trades_df'].to_csv(trades_csv_path, index=False)
        print(f"Saved trades to {trades_csv_path}")

        plt.figure(figsize=(12, 6))
        eq_series = res['equity_series']
        plt.plot(eq_series.index, eq_series.values, label=f'ORB ({range_mins}m)', color='orange', linewidth=1.5)
        plt.axhline(10000.0, color='gray', linestyle='--', alpha=0.7, label='Initial Capital ($10,000)')
        plt.title(f'ORB {range_mins}m Real Tick Backtest Equity Curve (XAUUSD Dukascopy)', fontsize=14, fontweight='bold')
        plt.xlabel('Date', fontsize=12)
        plt.ylabel('Equity ($)', fontsize=12)
        plt.grid(True, alpha=0.3)
        plt.legend(loc='upper left')
        plt.tight_layout()

        equity_png_path = os.path.join(output_dir, f'equity_ORB_{range_mins}m_ticks.png')
        plt.savefig(equity_png_path, dpi=300)
        plt.close()
        print(f"Saved equity curve to {equity_png_path}")

        summary_metrics.append(res['metrics'])

        print(f"=== METRICS FOR ORB {range_mins}m ===")
        for k, v in res['metrics'].items():
            print(f"{k}: {v}")

    summary_df = pd.DataFrame(summary_metrics)
    summary_df.to_csv(os.path.join(output_dir, 'metrics_ORB_ticks.csv'), index=False)


if __name__ == '__main__':
    main()
