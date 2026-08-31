import os
import sys
import unittest
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from scripts.run_ciclo5_higher_timeframes import compute_expanded_features_tf
from scripts.run_ciclo6_macro_features import compute_macro_features, ModelBacktester
from src.backtester import calculate_metrics

class TestCiclo6MacroFeatures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        dates = pd.date_range("2023-01-01 00:00", periods=500, freq="1h")
        np.random.seed(42)
        close = 1800.0 + np.cumsum(np.random.randn(500) * 0.5)
        high = close + np.random.rand(500) * 0.5
        low = close - np.random.rand(500) * 0.5
        open_p = close + np.random.randn(500) * 0.2

        cls.df_h1 = pd.DataFrame({
            'Open': open_p,
            'High': high,
            'Low': low,
            'Close': close,
            'Volume': 100
        }, index=dates)

        daily_dates = pd.date_range("2022-12-01", periods=60, freq="D")
        cls.macro_daily = pd.DataFrame({
            'DXY': 104.0 + np.cumsum(np.random.randn(60) * 0.2),
            'US10Y': 3.5 + np.cumsum(np.random.randn(60) * 0.05),
            'WTI': 75.0 + np.cumsum(np.random.randn(60) * 0.5),
            'XAGUSD': 23.0 + np.cumsum(np.random.randn(60) * 0.1)
        }, index=daily_dates)

    def test_compute_macro_features_alignment(self):
        df_h1_tech = compute_expanded_features_tf(self.df_h1, htf_rule='1D')
        df_combined, macro_cols = compute_macro_features(df_h1_tech, self.macro_daily)

        self.assertEqual(len(macro_cols), 9)
        for col in macro_cols:
            self.assertIn(col, df_combined.columns)
            self.assertFalse(df_combined[col].isna().any(), f"NaN found in macro feature {col}")

    def test_backtester_execution_macro_model(self):
        df_h1_tech = compute_expanded_features_tf(self.df_h1, htf_rule='1D')
        df_combined, macro_cols = compute_macro_features(df_h1_tech, self.macro_daily)
        df_combined['P_UP'] = 0.53

        params = {
            'InpThreshold': 0.52,
            'StartingLots': 0.03,
            'Perfil_Riesgo': 0
        }
        bt = ModelBacktester(df_combined, initial_balance=10000.0, params=params)
        bt.run()
        eq_df = pd.DataFrame(bt.equity_curve)
        metrics = calculate_metrics(bt.closed_trades, eq_df, 10000.0)
        self.assertIn('trades', metrics)
        self.assertIn('profit_factor', metrics)

if __name__ == '__main__':
    unittest.main()
