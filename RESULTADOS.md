# Resultados del Backtest Tick a Tick - Estrategia TREND (H1)

## Resumen Ejecutivo

Este documento reporta los resultados de la simulación **tick a tick** realista para la estrategia **TREND (Donchian + EMA)** en el marco temporal **H1** sobre datos de ticks reales de XAUUSD (Dukascopy).

La simulación evalúa las entradas al precio **Ask** (compras) y **Bid** (ventas), con gestión de Stop Loss (SL = $2.0 \times \text{ATR}$) y Take Profit (TP = $4.0 \times \text{ATR}$) evaluada **tick por tick** en orden cronológico estricto.

---

## 1. Reglas de la Estrategia TREND (H1)

- **Canal Donchian (20):** Máximo y mínimo de las 20 velas H1 previas (excluyendo la vela actual).
- **Medias Móviles:** EMA 50 y EMA 200 en H1.
- **Filtro de Tendencia:**
  - **COMPRA:** Cierre H1 > Donchian High(20) **Y** EMA 50 > EMA 200. Entrada ejecutada al precio Ask del primer tick de la nueva hora.
  - **VENTA:** Cierre H1 < Donchian Low(20) **Y** EMA 50 < EMA 200. Entrada ejecutada al precio Bid del primer tick de la nueva hora.
- **Gestión de Riesgo:**
  - **Stop Loss (SL):** $2.0 \times \text{ATR}(14)$ evaluado en cada tick (Bid para COMPRA, Ask para VENTA).
  - **Take Profit (TP):** $4.0 \times \text{ATR}(14)$ ($2.0 \times$ distancia del SL) evaluado en cada tick.
  - **Tamaño de Posición:** 1 unidad fija.
  - **Límite:** 1 posición activa a la vez.
  - **Costos:** Comisión = $0, Slippage = $0 (Spread real implícito en el Bid/Ask de cada tick).

---

## 2. Métricas de Rendimiento (TREND-H1)

| Métrica | Resultado |
|---|:---:|
| **Estrategia** | TREND (Donchian+EMA) H1 Ticks |
| **Período Evaluado** | Enero - Mayo 2024 (Ticks Dukascopy) |
| **Nº de Operaciones** | 8 |
| **Beneficio Neto ($)** | -$45.34 |
| **Win Rate (%)** | 12.50% |
| **Profit Factor** | 0.29 |
| **Sharpe Ratio** | -26.30 |
| **Drawdown Máximo ($)** | $63.71 |
| **Drawdown Máximo (%)** | 0.64% |
| **Promedio Ganadora ($)** | +$18.37 |
| **Promedio Perdedora ($)** | -$9.10 |

---

## 3. Archivos Generados

- **Operaciones detalladas (CSV):** `resultados/trades_TREND_H1_ticks.csv`
- **Gráfica de Equidad (PNG):** `resultados/equity_TREND_H1_ticks.png`
