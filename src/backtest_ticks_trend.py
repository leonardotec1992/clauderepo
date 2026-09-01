"""
Tick-by-tick backtester for Strategy 1: TREND (Donchian + EMA) on H1 timeframe.

Data source: Dukascopy XAUUSD tick files (.csv.gz) in datos/ticks_dukascopy/
Execution rules:
- Signal on H1 candle completion (Donchian(20) break + EMA50 vs EMA200 filter).
- Signal evaluated at candle completion (hour boundary). If no position is open, entry executes on the first tick of the new hour.
- BUY fills at Ask, SELL fills at Bid.
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

from src.indicators import compute_ema, compute_donchian, compute_atr


def build_h1_candles_from_ticks(tick_files: List[str]) -> pd.DataFrame:
    """
    Pass 1: Reads tick files in chunks, aggregates ticks into H1 OHLC candles,
    and computes technical indicators (EMA50, EMA200, Donchian20, ATR14).
    """
    h1_bars_list = []

    for fpath in tick_files:
        print(f"Reading ticks for H1 aggregation: {os.path.basename(fpath)}...")
        chunks = pd.read_csv(fpath, chunksize=500000)
        for chunk in chunks:
            chunk['timestamp'] = pd.to_datetime(chunk['timestamp'])
            # Resample bid prices to H1 OHLC
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
    # Combine bars belonging to the same hour across chunks
    full_h1 = full_h1.groupby(full_h1.index).agg({
        'open': 'first',
        'high': 'max',
        'low': 'min',
        'close': 'last'
    }).sort_index()

    # Calculate indicators
    full_h1['ema50'] = compute_ema(full_h1['close'], 50)
    full_h1['ema200'] = compute_ema(full_h1['close'], 200)
    full_h1['donchian_high_20'], full_h1['donchian_low_20'] = compute_donchian(full_h1, 20)
    full_h1['atr14'] = compute_atr(full_h1, 14)

    # Generate signals on closed H1 candles
    # BUY: close > donchian_high_20 AND ema50 > ema200
    # SELL: close < donchian_low_20 AND ema50 < ema200
    buy_cond = (full_h1['close'] > full_h1['donchian_high_20']) & (full_h1['ema50'] > full_h1['ema200'])
    sell_cond = (full_h1['close'] < full_h1['donchian_low_20']) & (full_h1['ema50'] < full_h1['ema200'])

    full_h1['signal'] = 0
    full_h1.loc[buy_cond, 'signal'] = 1
    full_h1.loc[sell_cond, 'signal'] = -1

    return full_h1


def run_trend_h1_tick_backtest(tick_files: List[str], h1_df: pd.DataFrame, initial_capital: float = 10000.0) -> Dict[str, Any]:
    """
    Pass 2: Streams ticks line by line / chunk by chunk, executing orders
    and evaluating SL / TP tick-by-tick in chronological sequence.
    """
    # Create lookup map for signals: at the completion of bar at time T,
    # the signal becomes actionable at the start of next hour (T + 1 hour)
    # map key: hour timestamp -> dict{'signal': int, 'atr14': float}
    h1_signals = {}
    for idx, row in h1_df.iterrows():
        next_hour = idx + pd.Timedelta(hours=1)
        sig = int(row['signal'])
        atr = float(row['atr14'])
        if sig != 0 and not np.isnan(atr) and atr > 0:
            h1_signals[next_hour] = {'signal': sig, 'atr14': atr}

    trades = []
    equity = initial_capital
    position = None  # Dict holding active position details
    seen_hours = set()

    # Track equity curve over time (timestamp, equity)
    equity_curve = []

    for fpath in tick_files:
        print(f"Streaming ticks for tick-by-tick simulation: {os.path.basename(fpath)}...")
        chunks = pd.read_csv(fpath, chunksize=500000)

        for chunk in chunks:
            chunk['timestamp'] = pd.to_datetime(chunk['timestamp'])

            # Extract numpy arrays for fast row iteration
            timestamps = chunk['timestamp'].values
            bids = chunk['bid'].values
            asks = chunk['ask'].values

            for i in range(len(chunk)):
                ts = pd.Timestamp(timestamps[i])
                bid = bids[i]
                ask = asks[i]

                current_hour = ts.floor('h')
                is_new_hour = (current_hour not in seen_hours)

                if is_new_hour:
                    seen_hours.add(current_hour)
                    # Check if a signal arrived on this new hour
                    sig_info = h1_signals.get(current_hour, None)

                    # Try opening position at start of new hour if no position is open
                    if position is None and sig_info is not None:
                        sig = sig_info['signal']
                        atr_v = sig_info['atr14']
                        sl_dist = 2.0 * atr_v
                        tp_dist = 2.0 * sl_dist  # 4.0 * atr_v

                        if sig == 1:  # BUY
                            entry_price = ask  # BUY fills at Ask
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
                            entry_price = bid  # SELL fills at Bid
                            sl_p = entry_price + sl_dist
                            tp_p = entry_price - tp_dist
                            position = {
                                'type': 'SELL',
                                'entry_time': ts,
                                'entry_price': entry_price,
                                'sl': sl_p,
                                'tp': tp_p
                            }

                # Check position exit conditions (SL / TP) tick-by-tick
                if position is not None:
                    p_type = position['type']
                    sl_p = position['sl']
                    tp_p = position['tp']

                    if p_type == 'BUY':
                        sl_hit = (bid <= sl_p)
                        tp_hit = (bid >= tp_p)

                        if sl_hit or tp_hit:
                            exit_price = sl_p if sl_hit else tp_p
                            exit_reason = 'SL' if sl_hit else 'TP'
                            pnl = exit_price - position['entry_price']
                            equity += pnl

                            trades.append({
                                'strategy': 'TREND (Donchian+EMA)',
                                'type': 'BUY',
                                'entry_time': position['entry_time'],
                                'entry_price': position['entry_price'],
                                'exit_time': ts,
                                'exit_price': exit_price,
                                'sl': sl_p,
                                'tp': tp_p,
                                'pnl': pnl,
                                'return_pct': (pnl / initial_capital) * 100.0,
                                'exit_reason': exit_reason
                            })
                            position = None
                            equity_curve.append((ts, equity))

                    elif p_type == 'SELL':
                        sl_hit = (ask >= sl_p)
                        tp_hit = (ask <= tp_p)

                        if sl_hit or tp_hit:
                            exit_price = sl_p if sl_hit else tp_p
                            exit_reason = 'SL' if sl_hit else 'TP'
                            pnl = position['entry_price'] - exit_price
                            equity += pnl

                            trades.append({
                                'strategy': 'TREND (Donchian+EMA)',
                                'type': 'SELL',
                                'entry_time': position['entry_time'],
                                'entry_price': position['entry_price'],
                                'exit_time': ts,
                                'exit_price': exit_price,
                                'sl': sl_p,
                                'tp': tp_p,
                                'pnl': pnl,
                                'return_pct': (pnl / initial_capital) * 100.0,
                                'exit_reason': exit_reason
                            })
                            position = None
                            equity_curve.append((ts, equity))

            # End of chunk snapshot for equity curve
            equity_curve.append((ts, equity))

    # Close any open position at end of stream
    if position is not None:
        p_type = position['type']
        last_exit = ask if p_type == 'SELL' else bid
        pnl = (last_exit - position['entry_price']) if p_type == 'BUY' else (position['entry_price'] - last_exit)
        equity += pnl
        trades.append({
            'strategy': 'TREND (Donchian+EMA)',
            'type': p_type,
            'entry_time': position['entry_time'],
            'entry_price': position['entry_price'],
            'exit_time': ts,
            'exit_price': last_exit,
            'sl': position['sl'],
            'tp': position['tp'],
            'pnl': pnl,
            'return_pct': (pnl / initial_capital) * 100.0,
            'exit_reason': 'END'
        })
        equity_curve.append((ts, equity))

    trades_df = pd.DataFrame(trades)
    eq_times, eq_values = zip(*equity_curve) if equity_curve else ([], [])
    equity_series = pd.Series(eq_values, index=pd.to_datetime(eq_times))

    # Calculate performance metrics
    metrics = compute_tick_metrics(trades_df, equity_series, initial_capital, 'TREND (Donchian+EMA) H1 Ticks')

    return {
        'metrics': metrics,
        'trades_df': trades_df,
        'equity_series': equity_series
    }


def compute_tick_metrics(trades_df: pd.DataFrame, equity_series: pd.Series, initial_capital: float, strat_name: str) -> Dict[str, Any]:
    """Calculates strategy performance metrics."""
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

    # Drawdown calculation
    peak = equity_series.cummax()
    drawdown = equity_series - peak
    drawdown_pct = (drawdown / peak) * 100.0

    max_dd_usd = abs(drawdown.min())
    max_dd_pct = abs(drawdown_pct.min())

    # Daily returns Sharpe
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

    # Step 1: Build H1 candles and indicators
    h1_df = build_h1_candles_from_ticks(tick_files)
    print(f"Aggregated H1 candles count: {len(h1_df)} | Date range: {h1_df.index.min()} to {h1_df.index.max()}")

    # Step 2: Run tick-by-tick backtest
    res = run_trend_h1_tick_backtest(tick_files, h1_df)

    # Save results
    output_dir = 'resultados'
    os.makedirs(output_dir, exist_ok=True)

    trades_csv_path = os.path.join(output_dir, 'trades_TREND_H1_ticks.csv')
    res['trades_df'].to_csv(trades_csv_path, index=False)
    print(f"Saved trades to {trades_csv_path}")

    # Plot Equity Curve
    plt.figure(figsize=(12, 6))
    eq_series = res['equity_series']
    plt.plot(eq_series.index, eq_series.values, label='TREND (Donchian+EMA) H1', color='blue', linewidth=1.5)
    plt.axhline(10000.0, color='gray', linestyle='--', alpha=0.7, label='Initial Capital ($10,000)')
    plt.title('TREND-H1 Real Tick Backtest Equity Curve (XAUUSD Dukascopy)', fontsize=14, fontweight='bold')
    plt.xlabel('Date', fontsize=12)
    plt.ylabel('Equity ($)', fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.legend(loc='upper left')
    plt.tight_layout()

    equity_png_path = os.path.join(output_dir, 'equity_TREND_H1_ticks.png')
    plt.savefig(equity_png_path, dpi=300)
    plt.close()
    print(f"Saved equity curve to {equity_png_path}")

    print("\n=== PERFORMANCE METRICS ===")
    for k, v in res['metrics'].items():
        print(f"{k}: {v}")


if __name__ == '__main__':
    main()
