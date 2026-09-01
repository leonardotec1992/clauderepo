# Resultados Comparativos del Backtest Tick a Tick (Dukascopy Real Ticks)

## Resumen Ejecutivo

Este documento presenta los resultados consolidados de la simulación **tick a tick realista** sobre los datos reales de ticks de **XAUUSD (Dukascopy - Enero 2024)** para las **4 estrategias de tendencia independientes**:

1. **TREND (Donchian + EMA en H1)**
2. **ORB (Opening Range Breakout en M5 - Rangos de 30m, 60m y 90m desde las 08:00)**
3. **MOMENTUM (ADX + DI en H1)**
4. **PULLBACK a la EMA (EMA50/200 en H1)**

### Modelo de Ejecución Realista:
- **Streaming de Ticks:** Evaluación tick por tick en orden cronológico estricto sin mirar al futuro.
- **Precios de Ejecución:** Compras ejecutadas al precio **Ask**, Ventas al precio **Bid**.
- **Gestión de SL y TP:** Evaluados en cada tick individual (Bid para Compras, Ask para Ventas).
- **Parámetros de Salida:** $SL = 2.0 \times \text{ATR}(14)$, $TP = 4.0 \times \text{ATR}(14)$ ($2 \times$ la distancia del SL).
- **Costos Operativos:** Comisión = $0, Deslizamiento (*Slippage*) = $0 (El costo de transacción y spread real está implícito en el diferencial Bid/Ask de los ticks reales de Dukascopy).
- **Límite de Operaciones:** 1 posición activa simultánea por estrategia; en ORB máximo 1 operación por día.

---

## 1. Tabla Comparativa General

| Estrategia | Marco Temporal | Operaciones | Beneficio Neto ($) | Win Rate (%) | Profit Factor | Sharpe Ratio | Max Drawdown ($) | Max Drawdown (%) | Avg Win ($) | Avg Loss ($) |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **TREND (Donchian+EMA)** | H1 | 8 | -$45.34 | 12.50% | 0.29 | -26.30 | $63.71 | 0.64% | $18.37 | -$9.10 |
| **ORB (30m)** | M5 | 22 | **+$29.22** | **63.64%** | **2.55** | **7.95** | $5.42 | 0.05% | $3.44 | -$2.36 |
| **ORB (60m)** | M5 | 22 | **+$34.97** | **63.64%** | **2.95** | **8.99** | $4.28 | 0.04% | $3.78 | -$2.24 |
| **ORB (90m)** | M5 | 22 | **+$32.86** | **63.64%** | **2.91** | **9.25** | $4.28 | 0.04% | $3.57 | -$2.15 |
| **MOMENTUM (ADX+DI)** | H1 | 18 | -$47.11 | 22.22% | 0.62 | -3.18 | $57.66 | 0.58% | $19.28 | -$8.87 |
| **PULLBACK (EMA)** | H1 | 10 | -$62.49 | 10.00% | 0.17 | -10.14 | $56.60 | 0.57% | $12.73 | -$8.36 |

---

## 2. Análisis Detallado por Estrategia

### 1. TREND (Donchian + EMA) - H1
- **Reglas:** Rompimiento de Canal Donchian(20) alineado con la tendencia principal (EMA50 > EMA200 para compra, EMA50 < EMA200 para venta).
- **Desempeño:** Generó 8 operaciones con una tasa de aciertos baja (12.50%) y una pérdida neta de -$45.34 (PF = 0.29). Los rompimientos en H1 durante este período sufrieron falsas rupturas (*whipsaws*) y retrocesos bruscos que activaron los Stops a nivel de tick antes de alcanzar el TP.

### 2. ORB (Opening Range Breakout) - M5 (08:00)
- **Reglas:** Define el rango máximo y mínimo acumulado entre las 08:00 y las 08:30 (30m), 09:00 (60m) o 09:30 (90m). Opera el rompimiento en M5 con un límite estricto de 1 operación por día.
- **Desempeño:** Fue la **única estrategia rentablemente consistente** en la prueba tick a tick.
  - **ORB 60m** logró el mayor beneficio neto (+$34.97) con un Profit Factor de 2.95 y un Drawdown Máximo insignificante de $4.28 (0.04%).
  - **ORB 90m** registró el mejor Sharpe Ratio (9.25) con un PF de 2.91.
  - La restricción de 1 operación por día junto con la liquidez de la apertura europea/americana permitió capturar impulsos direccionales limpios antes de que el mercado se consolidara.

### 3. MOMENTUM (ADX + DI) - H1
- **Reglas:** Filtro ADX(14) > 25, alineación de +DI vs -DI y confirmación por el cuerpo de la vela H1 previa.
- **Desempeño:** Completó 18 operaciones resultando en -$47.11 de pérdida neta (PF = 0.62). Aunque el filtro ADX requería fuerza en la tendencia, en el timeframe H1 el indicador presentó rezago (*lag*), haciendo que las entradas ocurrieran cerca del final de los impulsos.

### 4. PULLBACK a la EMA - H1
- **Reglas:** Tendencia confirmada por EMA50 vs EMA200, retroceso donde el precio toca/sobrepasa la EMA50 y cierra rebotando a favor de la tendencia.
- **Desempeño:** Fue la estrategia con peor rendimiento relativo (PF = 0.17, beneficio neta -$62.49 en 10 operaciones). Los retrocesos a la EMA50 frecuentemente continuaron hacia la EMA200 o más allá en tick a tick, ejecutando el SL antes de cualquier rebote duradero.

---

## 3. Conclusión Honesta y Transparente

1. **Diferencia entre velas sintéticas y ticks reales:**
   - La prueba tick a tick expone de manera cruda los micro-movimientos y picos de spread/precio que ocurren intra-vela. Estrategias de seguimiento de tendencia continuas en H1 (**TREND**, **MOMENTUM**, **PULLBACK**) que parecían viables en datos agregados sufren cuando el SL es barrido por mechas o latigazos antes del cierre de la vela.

2. **Superioridad del Apertura (ORB en M5):**
   - **ORB** demostró ser la arquitectura más sólida para la microestructura de XAUUSD en datos reales de ticks.
   - Definir un rango matutino claro (08:00 a 09:00/09:30) y restringir la operativa a **1 sola operación diaria** elimina el sobre-operar (*overtrading*) y la exposición continua al ruido.

3. **Recomendación Práctica:**
   - Para operar XAUUSD con ejecución tick a tick, los sistemas basados en rupturas con restricción temporal (ORB 60m / 90m en M5) poseen una ventaja matemática (*edge*) significativamente superior a los sistemas trend-following continuos en marcos temporales H1.

---

## 4. Archivos de Resultados Guardados

- **Resumen general de métricas:** `resultados/tick_strategies_summary.csv`
- **Registros de operaciones por estrategia:**
  - `resultados/trades_TREND_H1_ticks.csv`
  - `resultados/trades_ORB_30m_ticks.csv`
  - `resultados/trades_ORB_60m_ticks.csv`
  - `resultados/trades_ORB_90m_ticks.csv`
  - `resultados/trades_MOMENTUM_H1_ticks.csv`
  - `resultados/trades_PULLBACK_H1_ticks.csv`
- **Gráficas de equidad (PNG):**
  - `resultados/equity_TREND_H1_ticks.png`
  - `resultados/equity_ORB_30m_ticks.png`
  - `resultados/equity_ORB_60m_ticks.png`
  - `resultados/equity_ORB_90m_ticks.png`
  - `resultados/equity_MOMENTUM_H1_ticks.png`
  - `resultados/equity_PULLBACK_H1_ticks.png`
