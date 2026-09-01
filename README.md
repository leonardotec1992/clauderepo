# Proyecto de Backtesting Multi-Estrategia para XAUUSD (Oro)

Este proyecto implementa y evalúa 4 estrategias de tendencia **INDEPENDIENTES** sobre velas de XAUUSD (Oro). El objetivo principal es medir de manera transparente y realista cuál estrategia (si alguna) posee una ventaja o beneficio consistente (*edge*), considerando costos de transacción realistas (spread).

---

## 1. Fuentes y Períodos de Datos

Los datos fueron obtenidos mediante `yfinance` utilizando el contrato de futuros de oro `GC=F` (referencia internacional para spot/futuros de XAUUSD).

| Marco Temporal | Fuente | Rango de Fechas Evaluado | Cantidad de Velas |
|---|---|---|---|
| **M5 (5 min)** | yfinance (`GC=F`) | 2026-06-22 a 2026-08-31 (~60 días) | 13,678 velas |
| **M15 (15 min)** | yfinance (`GC=F`) | 2026-06-22 a 2026-08-31 (~60 días) | 4,571 velas |
| **H1 (1 hora)** | yfinance (`GC=F`) | 2024-04-09 a 2026-08-31 (~24 meses) | 13,729 velas |

*Nota sobre datos locales:* Se incluyó el módulo `src/data_loader.py` preparado para leer archivos CSV locales exportados directamente de MetaTrader 5 (MT5) colocando los archivos en la carpeta `/data` o ejecutando `python main.py --csv <ruta_al_archivo.csv>`.

---

## 2. Reglas de las 4 Estrategias Evaluadas

Cada estrategia mantiene su propia posición de manera independiente (tamaño fijo de 1 unidad).

1. **TREND (Donchian + EMA):**
   - Canal Donchian (20): Máximo y mínimo de las 20 velas anteriores (excluye la vela actual).
   - Medias Móviles: EMA 50 y EMA 200.
   - **COMPRA:** Cierre > Donchian High(20) Y EMA 50 > EMA 200.
   - **VENTA:** Cierre < Donchian Low(20) Y EMA 50 < EMA 200.

2. **ORB (Opening Range Breakout):**
   - Hora de apertura: 08:00 UTC.
   - Rango: Máximo y mínimo de los primeros $N$ minutos tras la apertura.
   - **COMPRA:** Cierre rompe por encima del rango alto.
   - **VENTA:** Cierre rompe por debajo del rango bajo.
   - **Límite:** Máximo 1 operación por día.
   - **Prueba de Robustez:** Evaluado por separado en rangos de **30 min**, **60 min** y **90 min**.

3. **MOMENTUM (ADX + DI):**
   - Filtro: ADX(14) > 25.
   - **COMPRA:** ADX > 25 Y +DI > -DI Y Vela actual alcista (Cierre > Apertura).
   - **VENTA:** ADX > 25 Y -DI > +DI Y Vela actual bajista (Cierre < Apertura).

4. **PULLBACK a EMA:**
   - Medias Móviles: EMA 50 y EMA 200.
   - **COMPRA:** EMA 50 > EMA 200 Y Mínimo <= EMA 50 Y Cierre > EMA 50.
   - **VENTA:** EMA 50 < EMA 200 Y Máximo >= EMA 50 Y Cierre < EMA 50.

---

## 3. Gestión de Riesgo y Costos Operativos

- **Stop Loss (SL):** $2.0 \times \text{ATR}(14)$
- **Take Profit (TP):** $4.0 \times \text{ATR}(14)$ (Ratio Riesgo:Beneficio de 1:2)
- **Tamaño de posición:** 1.0 unidad fija.
- **Spread / Comisiones (Costos Realistas):** Penalización de **0.30 puntos ($0.30/oz)** en cada precio de entrada.
- **Posición por estrategia:** 1 posición activa simultánea por estrategia.

---

## 4. Resultados del Backtest (Tabla Comparativa)

### Marco Temporal M5 (5 Minutos - ~60 Días)

| Estrategia | Operaciones | Net Profit ($) | Win Rate (%) | Profit Factor | Sharpe | Max DD ($) | Max DD (%) | Avg Win ($) | Avg Loss ($) |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **TREND (Donchian+EMA)** | 297 | -$393.19 | 31.65% | 0.84 | -0.16 | $562.75 | 5.63% | $22.63 | -$12.41 |
| **ORB (30m)** | 50 | -$234.49 | 24.00% | 0.57 | -0.24 | $345.15 | 3.44% | $26.07 | -$14.40 |
| **ORB (60m)** | 48 | -$84.74 | 31.25% | 0.84 | -0.07 | $178.91 | 1.78% | $28.66 | -$15.59 |
| **ORB (90m)** | 47 | -$34.27 | 31.91% | 0.93 | -0.03 | $185.68 | 1.84% | $29.94 | -$15.11 |
| **MOMENTUM (ADX+DI)** | 316 | **+$247.42** | **36.71%** | **1.10** | **0.10** | $209.96 | 2.07% | $24.50 | -$12.97 |
| **PULLBACK (EMA)** | 271 | -$373.97 | 34.69% | 0.84 | -0.16 | $644.05 | 6.44% | $20.98 | -$13.25 |

### Marco Temporal M15 (15 Minutos - ~60 Días)

| Estrategia | Operaciones | Net Profit ($) | Win Rate (%) | Profit Factor | Sharpe | Max DD ($) | Max DD (%) | Avg Win ($) | Avg Loss ($) |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **TREND (Donchian+EMA)** | 88 | **+$273.07** | **40.91%** | **1.24** | **0.21** | $125.05 | 1.24% | $39.42 | -$22.04 |
| **ORB (30m)** | 48 | -$233.93 | 22.92% | 0.69 | -0.26 | $460.49 | 4.52% | $47.46 | -$20.43 |
| **ORB (60m)** | 43 | -$209.37 | 23.26% | 0.71 | -0.22 | $363.53 | 3.58% | $52.03 | -$22.11 |
| **ORB (90m)** | 39 | **+$61.11** | 33.33% | 1.10 | 0.06 | $127.14 | 1.25% | $50.45 | -$22.87 |
| **MOMENTUM (ADX+DI)** | 122 | -$269.58 | 28.69% | 0.86 | -0.16 | $700.52 | 6.94% | $47.00 | -$22.01 |
| **PULLBACK (EMA)** | 90 | **+$121.68** | 35.56% | 1.11 | 0.11 | $211.70 | 2.09% | $37.85 | -$18.79 |

### Marco Temporal H1 (1 Hora - ~2 Años / 730 Días)

| Estrategia | Operaciones | Net Profit ($) | Win Rate (%) | Profit Factor | Sharpe | Max DD ($) | Max DD (%) | Avg Win ($) | Avg Loss ($) |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **TREND (Donchian+EMA)** | 285 | **+$1,363.39** | **37.19%** | **1.25** | **0.21** | $556.27 | 4.95% | $63.75 | -$30.13 |
| **ORB (30m)** | 342 | -$0.91 | 34.80% | 1.00 | 0.01 | $961.62 | 8.77% | $67.69 | -$36.12 |
| **ORB (60m)** | 342 | -$0.91 | 34.80% | 1.00 | 0.01 | $961.62 | 8.77% | $67.69 | -$36.12 |
| **ORB (90m)** | 311 | **+$223.03** | 34.41% | 1.03 | 0.04 | $687.24 | 6.65% | $67.32 | -$34.22 |
| **MOMENTUM (ADX+DI)** | 384 | -$30.41 | 33.33% | 1.00 | 0.01 | $1,054.80 | 10.16% | $71.20 | -$35.72 |
| **PULLBACK (EMA)** | 225 | **+$97.84** | 34.22% | 1.02 | 0.02 | $709.46 | 7.09% | $65.34 | -$33.33 |

---

## 5. Gráficas Generadas

Las curvas de equidad y los gráficos de drawdown se guardaron automáticamente en la carpeta `/resultados`:
- `resultados/equity_curves_M5.png` y `resultados/drawdown_M5.png`
- `resultados/equity_curves_M15.png` y `resultados/drawdown_M15.png`
- `resultados/equity_curves_H1.png` y `resultados/drawdown_H1.png`

---

## 6. Conclusión Honesta y Transparente

1. **Rendimiento en M5 (Marco temporal original de la solicitud):**
   - En velas M5 de 60 días, la mayoría de las estrategias de tendencia puras sufren debido al "ruido" del mercado y a los costos de fricción (spread de $0.30 por entrada).
   - **TREND (Donchian+EMA)** y **PULLBACK (EMA)** pierden dinero en M5 ($393 y $374 de pérdida respectivamente, Profit Factor 0.84).
   - **MOMENTUM (ADX+DI)** fue la única con beneficio positivo en M5 (+$247.42, PF 1.10), ya que el filtro de ADX > 25 ayudó a evitar mercados laterales ruidosos.

2. **Prueba de Robustez de ORB (Opening Range Breakout):**
   - Extender la ventana del rango inicial mejoró progresivamente los resultados (de 30m a 60m y luego 90m). En todos los timeframes, **ORB (90m)** superó holgadamente a ORB (30m) y ORB (60m), reduciendo falsas rupturas matutinas en el oro.

3. **Comportamiento en Marcos Temporales Mayores (M15 y H1):**
   - **TREND (Donchian + EMA)** demostró la mayor solidez a mayor plazo. En **H1 (2 años de historia)** generó **+$1,363.39** con un **Profit Factor de 1.25** y un **Max Drawdown de 4.95%**. En M15 también obtuvo beneficio (+$273.07, PF 1.24).
   - En el oro, las tendencias de alta temporalidad (H1) filtran los latigazos provocados por el spread retail en intradía (M5).

4. **Advertencias de Limitaciones:**
   - **Spread y Deslizamiento (Slippage):** Un spread menor (ej. ecn $0.10 - $0.15) incrementaría sustancialmente la rentabilidad en M5, mientras que un spread alto o un deslizamiento en noticias liquidaría las ganancias de ORB.
   - **Rentabilidad Pasada vs. Futura:** Un backtest de 2 meses en M5 o de 2 años en H1 **no garantiza** resultados en cuenta real.

---

## 7. Instrucciones para Ejecutar el Proyecto

```bash
# 1. Instalar dependencias
pip install -r requirements.txt

# 2. Ejecutar backtest completo (Descarga datos automáticos de yfinance)
python main.py

# 3. (Opcional) Ejecutar backtest utilizando un archivo CSV exportado desde MT5
python main.py --csv data/XAUUSD_M5.csv --spread 0.30
```
