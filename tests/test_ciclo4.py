import os
import sys
import unittest
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from scripts.run_ciclo4_redesign import compute_expanded_features, ModelBacktester
from src.backtester import calculate_metrics

class TestCiclo4Redesign(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Create a small dummy M5 dataset
        dates = pd.date_range("2023-01-01 00:00", periods=200, freq="5min")
        np.random.seed(42)
        close = 1800.0 + np.cumsum(np.random.randn(200) * 0.5)
        high = close + np.random.rand(200) * 0.5
        low = close - np.random.rand(200) * 0.5
        open_p = close + np.random.randn(200) * 0.2

        cls.df_dummy = pd.DataFrame({
            'Open': open_p,
            'High': high,
            'Low': low,
            'Close': close,
            'Volume': 100
        }, index=dates)

    def test_feature_computation(self):
        df_feat = compute_expanded_features(self.df_dummy)
        feature_cols = [
            'sRSI', 'sCCI', 'sSlope', 'sReturn', 'sTrend',
            'ATR_pct_rank', 'RSI_7', 'RSI', 'RSI_21',
            'BB_pctB', 'BB_bandwidth', 'MACD_hist', 'ADX',
            'H1_dist_EMA50', 'H1_dist_EMA200', 'H1_dir_EMA50', 'H1_dir_EMA200', 'H1_EMA50_vs_EMA200',
            'Sess_Asia', 'Sess_London', 'Sess_NY', 'Sess_Out',
            'Day_Mon', 'Day_Tue', 'Day_Wed', 'Day_Thu', 'Day_Fri'
        ]
        for col in feature_cols:
            self.assertIn(col, df_feat.columns, f"Missing feature column {col}")

    def test_backtester_execution(self):
        df_feat = compute_expanded_features(self.df_dummy)
        df_feat['P_UP'] = 0.53
        params = {
            'InpThreshold': 0.52,
            'StartingLots': 0.03,
            'Perfil_Riesgo': 0
        }
        bt = ModelBacktester(df_feat, initial_balance=10000.0, params=params)
        bt.run()
        eq_df = pd.DataFrame(bt.equity_curve)
        metrics = calculate_metrics(bt.closed_trades, eq_df, 10000.0)
        self.assertIn('trades', metrics)
        self.assertIn('profit_factor', metrics)

if __name__ == '__main__':
    unittest.main()
