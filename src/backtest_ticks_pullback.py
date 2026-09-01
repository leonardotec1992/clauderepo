"""
Tick-by-tick backtester for Strategy 4: PULLBACK to EMA on H1 timeframe.

Data source: Dukascopy XAUUSD tick files (.csv.gz) in datos/ticks_dukascopy/
Execution rules:
- Signal evaluated on H1 candle completion:
  - BUY if EMA50 > EMA200 AND low <= EMA50 AND close > EMA50.
  - SELL if EMA50 < EMA200 AND high >= EMA50 AND close < EMA50.
- BUY fills at Ask, SELL fills at Bid on the first tick of the next hour.
- SL evaluated tick-by-tick at 2.0x ATR(14 in H1).
- TP evaluated tick-by-tick at 4.0x ATR(14 in H1) (2.0x SL distance).
- Position size: 1 fixed unit. Single position at a time.
- Commission = 0, Slippage = 0.
"""

import os
import glob
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from typing import Dict, List, Any

from src.indicators import compute_ema, compute_atr


def build_h1_candles_from_ticks(tick_files: List[str]) -> pd.DataFrame:
    """
    Pass 1: Reads tick files, aggregates ticks into H1 OHLC candles,
    and computes EMA50, EMA200, and ATR(14) on H1 candles.
    """
    h1_bars_list = []

    for fpath in tick_files:
        print(f"Reading ticks for H1 aggregation: {os.path.basename(fpath)}...")
        chunks = pd.read_csv(fpath, chunksize=500000)
        for chunk in chunks:
            chunk['timestamp'] = pd.to_datetime(chunk['timestamp'])
            chunk.set_index('timestamp', inplace=True)
            resampled = chunk['bid'].resample('1h').agg(
                open='first',
                high='max',
                low='min',
                close='last'
            ).dropna()
            if not resampled.empty:
                h1_bars_list.append(resampled)

    if not h1_bars_list:
        raise ValueError("No tick data loaded!")

    full_h1 = pd.concat(h1_bars_list)
    full_h1 = full_h1.groupby(full_h1.index).agg({
        'open': 'first',
        'high': 'max',
        'low': 'min',
        'close': 'last'
    }).sort_index()

    full_h1['ema50'] = compute_ema(full_h1['close'], 50)
    full_h1['ema200'] = compute_ema(full_h1['close'], 200)
    full_h1['atr14'] = compute_atr(full_h1, 14)

    buy_cond = (full_h1['ema50'] > full_h1['ema200']) & (full_h1['low'] <= full_h1['ema50']) & (full_h1['close'] > full_h1['ema50'])
    sell_cond = (full_h1['ema50'] < full_h1['ema200']) & (full_h1['high'] >= full_h1['ema50']) & (full_h1['close'] < full_h1['ema50'])

    full_h1['signal'] = 0
    full_h1.loc[buy_cond, 'signal'] = 1
    full_h1.loc[sell_cond, 'signal'] = -1

    return full_h1


def run_pullback_tick_backtest(tick_files: List[str], h1_df: pd.DataFrame, initial_capital: float = 10000.0) -> Dict[str, Any]:
    """
    Pass 2: Fast vectorized tick-by-tick backtester for PULLBACK H1.
    """
    # Key: hour timestamp when trade can execute -> dict(signal, atr14)
    h1_signals = {}
    for idx, row in h1_df.iterrows():
        next_hour = idx + pd.Timedelta(hours=1)
        sig = int(row['signal'])
        atr = float(row['atr14'])
        if sig != 0 and not np.isnan(atr) and atr > 0:
            h1_signals[next_hour] = {'signal': sig, 'atr14': atr}

    trades = []
    equity = initial_capital
    position = None
    seen_hours = set()
    equity_curve = []

    strat_label = "PULLBACK (EMA) H1 Ticks"

    for fpath in tick_files:
        print(f"Streaming ticks for PULLBACK H1 simulation: {os.path.basename(fpath)}...")
        chunks = pd.read_csv(fpath, chunksize=500000)

        for chunk in chunks:
            chunk['timestamp'] = pd.to_datetime(chunk['timestamp'])
            chunk['h1'] = chunk['timestamp'].dt.floor('1h')

            timestamps = chunk['timestamp'].values
            bids = chunk['bid'].values
            asks = chunk['ask'].values
            h1s = chunk['h1'].values

            i = 0
            n = len(chunk)

            while i < n:
                ts = pd.Timestamp(timestamps[i])
                curr_hour = pd.Timestamp(h1s[i])

                if position is not None:
                    p_type = position['type']
                    sl_p = position['sl']
                    tp_p = position['tp']

                    if p_type == 'BUY':
                        sl_hits = np.where(bids[i:] <= sl_p)[0]
                        tp_hits = np.where(bids[i:] >= tp_p)[0]
                    else:  # SELL
                        sl_hits = np.where(asks[i:] >= sl_p)[0]
                        tp_hits = np.where(asks[i:] <= tp_p)[0]

                    idx_sl = sl_hits[0] if len(sl_hits) > 0 else None
                    idx_tp = tp_hits[0] if len(tp_hits) > 0 else None

                    if idx_sl is None and idx_tp is None:
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
                        pnl = (exit_price - position['entry_price']) if p_type == 'BUY' else (position['entry_price'] - exit_price)
                        equity += pnl

                        trades.append({
                            'strategy': 'PULLBACK (EMA)',
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
                    if curr_hour not in seen_hours:
                        seen_hours.add(curr_hour)
                        sig_info = h1_signals.get(curr_hour, None)

                        if sig_info is not None:
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

                    if position is None:
                        next_hour_offsets = np.where(h1s[i:] != h1s[i])[0]
                        if len(next_hour_offsets) > 0:
                            i = i + next_hour_offsets[0]
                        else:
                            i = n

            last_chunk_ts = pd.Timestamp(timestamps[-1])
            equity_curve.append((last_chunk_ts, equity))

    if position is not None:
        p_type = position['type']
        last_exit = ask if p_type == 'SELL' else bid
        pnl = (last_exit - position['entry_price']) if p_type == 'BUY' else (position['entry_price'] - last_exit)
        equity += pnl
        trades.append({
            'strategy': 'PULLBACK (EMA)',
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

    h1_df = build_h1_candles_from_ticks(tick_files)
    print(f"Aggregated H1 candles count: {len(h1_df)} | Date range: {h1_df.index.min()} to {h1_df.index.max()}")

    res = run_pullback_tick_backtest(tick_files, h1_df)

    output_dir = 'resultados'
    os.makedirs(output_dir, exist_ok=True)

    trades_csv_path = os.path.join(output_dir, 'trades_PULLBACK_H1_ticks.csv')
    res['trades_df'].to_csv(trades_csv_path, index=False)
    print(f"Saved trades to {trades_csv_path}")

    plt.figure(figsize=(12, 6))
    eq_series = res['equity_series']
    plt.plot(eq_series.index, eq_series.values, label='PULLBACK (EMA) H1', color='purple', linewidth=1.5)
    plt.axhline(10000.0, color='gray', linestyle='--', alpha=0.7, label='Initial Capital ($10,000)')
    plt.title('PULLBACK-H1 Real Tick Backtest Equity Curve (XAUUSD Dukascopy)', fontsize=14, fontweight='bold')
    plt.xlabel('Date', fontsize=12)
    plt.ylabel('Equity ($)', fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.legend(loc='upper left')
    plt.tight_layout()

    equity_png_path = os.path.join(output_dir, 'equity_PULLBACK_H1_ticks.png')
    plt.savefig(equity_png_path, dpi=300)
    plt.close()
    print(f"Saved equity curve to {equity_png_path}")

    print("\n=== PERFORMANCE METRICS ===")
    for k, v in res['metrics'].items():
        print(f"{k}: {v}")


if __name__ == '__main__':
    main()
