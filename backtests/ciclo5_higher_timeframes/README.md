# Ciclo 5: Diagnóstico y Modelo Ajustado en Temporalidades Mayores (H1 y H4)

## Contexto y Objetivo

En los ciclos anteriores (Ciclos 1 al 4) se evaluó rigurosamente la estrategia y la arquitectura de señal probabilística sobre la temporalidad **M5** de XAUUSD. El diagnóstico del Ciclo 4 reveló que las 25 features técnicas individuales (tanto los 5 indicadores originales como 20 variables ampliadas) presentan valores de **ROC-AUC entre 0.472 y 0.526** (donde 0.50 representa azar puro) e **IC de Spearman $\le 0.044$**. Al entrenar una Regresión Logística L2 completa sobre M5, el AUC Out-Of-Sample (OOS) fue de **0.5160**, resultando en pérdidas sistemáticas al enfrentar los costos reales de transacción (30 pips de spread + $3.50/lote de comisión).

Antes de incorporar fuentes de datos externas (macro, flujo de órdenes, cross-asset), el cliente solicitó probar la hipótesis de que el problema reside en la **Alta Frecuencia (M5)**: en temporalidades mayores (H1 y H4), la fricción fija del spread/comisión pesa sustancialmente menos respecto al rango típico de movimiento del precio, y los mismos indicadores técnicos podrían capturar un contenido informativo superior.

El objetivo del **Ciclo 5** es replicar exactamente la metodología del Ciclo 4 sobre dos temporalidades mayores:
1. **Temporalidad H1:** Resampleo de datos M5 a velas H1, usando velas Diarias (D1) como referencia de tendencia superior y horizontes $K=1, 3, 6$ velas H1.
2. **Temporalidad H4:** Resampleo de datos M5 a velas H4, usando velas Diarias (D1) como referencia de tendencia superior y horizontes $K=1, 3, 6$ velas H4.

---

## Metodología y Split de Datos

- **Fuente de Datos:** Resampleo causal (sin look-ahead: `Open`=primero, `High`=máximo, `Low`=mínimo, `Close`=último del período) a partir de las 423,044 velas M5 de XAUUSD (2019–2024).
- **Split Cronológico:** 70% In-Sample (IS) / 30% Out-Of-Sample (OOS).
  - **H1:** Total 35,223 velas analizadas.
    - IS: 2019-01-14 a 2023-03-16 (24,596 velas).
    - OOS: 2023-03-16 a 2024-12-31 (10,627 velas).
  - **H4:** Total 9,072 velas analizadas.
    - IS: 2019-02-18 a 2023-03-16 (6,291 velas).
    - OOS: 2023-03-16 a 2024-12-31 (2,781 velas).
- **Costos de Transacción:** Spread de 30 puntos ($0.30/oz) y comisión de $3.50 por lote round-turn.

---

## Parte 1: Diagnóstico de Contenido Informativo (In-Sample)

Se calcularon el **Information Coefficient (IC de Spearman)** y el **ROC-AUC** sobre el período In-Sample para cada una de las 25 features en horizontes $K=1, 3, 6$ velas.

### Diagnóstico H1 (Top 10 Features por |IC| en K=1)

| Feature | Categoria | Spearman IC (K=1) | p-value (K=1) | ROC-AUC (K=1) | ROC-AUC (K=3) | ROC-AUC (K=6) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `sReturn` | Original | -0.041181 | 1.04e-10 | 0.4732 | 0.4908 | 0.4965 |
| `sSlope` | Original | -0.039987 | 3.54e-10 | 0.4749 | 0.4905 | 0.4969 |
| `RSI_7` | Momentum | -0.022632 | 3.86e-04 | 0.4818 | 0.4947 | 0.4988 |
| `BB_pctB` | Bollinger | -0.017458 | 6.18e-03 | 0.4849 | 0.4970 | 0.5005 |
| `sCCI` | Original | 0.015620 | 1.43e-02 | 0.5136 | 0.5042 | 0.5015 |
| `sRSI` | Original | 0.014135 | 2.66e-02 | 0.5136 | 0.5039 | 0.5011 |
| `RSI` | Momentum | -0.014135 | 2.66e-02 | 0.4864 | 0.4961 | 0.4989 |
| `MACD_hist` | MACD | -0.012137 | 5.70e-02 | 0.4903 | 0.4960 | 0.4981 |
| `Day_Mon` | Dummies | -0.011176 | 7.96e-02 | 0.4947 | 0.4921 | 0.4891 |
| `RSI_21` | Momentum | -0.009958 | 1.18e-01 | 0.4889 | 0.4975 | 0.4998 |

### Diagnóstico H4 (Top 10 Features por |IC| en K=1)

| Feature | Categoria | Spearman IC (K=1) | p-value (K=1) | ROC-AUC (K=1) | ROC-AUC (K=3) | ROC-AUC (K=6) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `ADX` | Tendencia | 0.025868 | 4.02e-02 | 0.5135 | 0.5085 | 0.4893 |
| `Sess_Asia` | Dummies | -0.023487 | 6.25e-02 | 0.4963 | 0.4976 | 0.4978 |
| `Day_Fri` | Dummies | 0.022448 | 7.50e-02 | 0.5105 | 0.5065 | 0.5011 |
| `BB_bandwidth` | Volatilidad | 0.018949 | 1.33e-01 | 0.5132 | 0.5049 | 0.4922 |
| `Day_Mon` | Dummies | -0.016359 | 1.95e-01 | 0.4937 | 0.4979 | 0.4998 |
| `Day_Tue` | Dummies | -0.014382 | 2.54e-01 | 0.4964 | 0.4936 | 0.4979 |
| `ATR_pct_rank` | Volatilidad | 0.013618 | 2.80e-01 | 0.5131 | 0.5064 | 0.4921 |
| `HTF_EMA50_vs_EMA200` | HTF Trend | 0.013607 | 2.81e-01 | 0.5080 | 0.5050 | 0.5005 |
| `Sess_Out` | Dummies | 0.009359 | 4.58e-01 | 0.5021 | 0.5015 | 0.5020 |
| `RSI` | Momentum | -0.008775 | 4.87e-01 | 0.4902 | 0.4947 | 0.4950 |

---

## Parte 2: Modelo Ajustado (Regresión Logística L2)

Se entrenó una Regresión Logística L2 estandarizada mediante `StandardScaler` con tuning interno del parámetro $C$ en la partición IS.

### Resumen de Modelos Ajustados

- **H1:** Parámetro óptimo $C = 0.001$.
  - **AUC In-Sample (IS):** `0.53305`
  - **AUC Out-Of-Sample (OOS):** `0.51481`
- **H4:** Parámetro óptimo $C = 0.001$.
  - **AUC In-Sample (IS):** `0.53223`
  - **AUC Out-Of-Sample (OOS):** `0.52676`

---

## Resultados de Backtest (Señal Aislada: Lote Fijo 0.03, SL/TP ATR)

### Resultados Backtest H1

| Threshold | Set | Trades | Net Profit ($) | Profit Factor | Win Rate (%) | Max DD (%) | Sharpe | OnTester |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 0.52 | IS | 398 | -$450.51 | 0.92 | 39.70% | 9.20% | -0.27 | 0.00 |
| 0.52 | OOS | 131 | $71.80 | 1.04 | 42.00% | 3.00% | 0.20 | 0.00 |
| 0.53 | IS | 288 | -$372.54 | 0.90 | 39.58% | 8.30% | -0.28 | 0.00 |
| 0.53 | OOS | 94 | $56.73 | 1.04 | 41.49% | 3.80% | 0.17 | 0.00 |
| 0.54 | IS | 177 | $398.69 | 1.19 | 45.76% | 3.10% | 0.47 | 11.83 |
| 0.54 | OOS | 53 | $213.52 | 1.33 | 45.28% | 1.90% | 0.70 | 7.42 |
| 0.55 | IS | 83 | $228.74 | 1.23 | 45.78% | 1.90% | 0.47 | 8.93 |
| 0.55 | OOS | 21 | $176.68 | 1.75 | 52.38% | 1.00% | 1.00 | 0.00 |

*Nota sobre H1:* En OOS a $Th=0.55$ el número de trades baja a solo **21 operaciones en casi 2 años** (muestra insuficiente, $< 40$ trades).

### Resultados Backtest H4

| Threshold | Set | Trades | Net Profit ($) | Profit Factor | Win Rate (%) | Max DD (%) | Sharpe | OnTester |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 0.52 | IS | 19 | $222.26 | 2.07 | 57.89% | 0.70 | 0.96 | 0.00 |
| 0.52 | OOS | 0 | $0.00 | 0.00 | 0.00% | 0.00% | 0.00 | 0.00 |
| 0.53 | IS | 11 | $102.41 | 1.76 | 54.55% | 0.70 | 0.63 | 0.00 |
| 0.53 | OOS | 0 | $0.00 | 0.00 | 0.00% | 0.00% | 0.00 | 0.00 |
| 0.54 | IS | 6 | $43.35 | 1.54 | 50.00% | 0.70 | 0.38 | 0.00 |
| 0.54 | OOS | 0 | $0.00 | 0.00 | 0.00% | 0.00% | 0.00 | 0.00 |
| 0.55 | IS | 1 | $43.85 | 999.00 | 100.00% | 0.40 | 0.00 | 0.00 |
| 0.55 | OOS | 0 | $0.00 | 0.00 | 0.00% | 0.00% | 0.00 | 0.00 |

⚠️ **Alerta Crítica de Tamaño de Muestra en H4:**
Debido a que el modelo $L2$ con $C=0.001$ asigna pesos muy pequeños a las 25 features (dada la falta de señal en los datos), las probabilidades calculadas se comprimen fuertemente alrededor de $0.500 \pm 0.015$. Como consecuencia, en **H4 OOS no se genera NINGUNA operación (0 trades)** para los umbrales $\ge 0.52$. La muestra en H4 OOS es **totalmente insuficiente** para extraer conclusiones estadísticamente válidas.

---

## Evaluaciones de los 4 Perfiles de Riesgo (Etapa B)

### Perfiles de Riesgo H1 ($Th = 0.53$)

| Perfil | IS Trades | IS Net Profit ($) | IS PF | IS Max DD (%) | OOS Trades | OOS Net Profit ($) | OOS PF | OOS Max DD (%) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| MANUAL | 288 | -$10,007.84 | 0.68 | 100.0% | 94 | -$6,885.51 | 0.80 | 94.4% |
| CONSERVADOR | 288 | -$1,093.89 | 0.87 | 16.2% | 94 | -$144.96 | 0.94 | 8.1% |
| BALANCEADO | 288 | -$1,568.89 | 0.91 | 27.8% | 94 | -$79.63 | 0.98 | 16.1% |
| AGRESIVO | 288 | -$2,683.58 | 0.91 | 46.3% | 94 | -$197.04 | 0.98 | 27.3% |

*Comentario Etapa B H1:* Aunque el backtest simple a lote fijo mostró ligera ganancia en OOS por una racha favorable de bajo tamaño muestral, al activar el apalancamiento por riesgo y las capas de martingala en los perfiles de riesgo, **todos los 4 perfiles resultan en pérdidas netas tanto en IS como en OOS**.

### Perfiles de Riesgo H4 ($Th = 0.53$)

| Perfil | IS Trades | IS Net Profit ($) | IS PF | IS Max DD (%) | OOS Trades | OOS Net Profit ($) | OOS PF | OOS Max DD (%) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| MANUAL | 11 | $10,727.53 | 2.19 | 50.7% | 0 | $0.00 | 0.00 | 0.0% |
| CONSERVADOR | 11 | $197.79 | 1.86 | 1.1% | 0 | $0.00 | 0.00 | 0.0% |
| BALANCEADO | 11 | $378.25 | 1.79 | 2.4% | 0 | $0.00 | 0.00 | 0.0% |
| AGRESIVO | 11 | $693.78 | 1.78 | 4.4% | 0 | $0.00 | 0.00 | 0.0% |

---

## Comparación Obligatoria: M5 vs H1 vs H4

| Temporalidad | Barras IS | Barras OOS | AUC In-Sample (IS) | AUC Out-Of-Sample (OOS) | Conclusión Predictiva |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **M5** (Ciclo 4) | 295,130 | 126,913 | **0.5297** | **0.5160** | Ruido puro. Sin capacidad discriminativa. |
| **H1** (Ciclo 5) | 24,596 | 10,627 | **0.5331** | **0.5148** | Ruido puro. La capacidad predictiva OOS NO mejora. |
| **H4** (Ciclo 5) | 6,291 | 2,781 | **0.5322** | **0.5268** | Ruido/Sobreajuste muestral alto. 0 trades en OOS. |

---

## Conclusión Crítica Honesta

1. **La capacidad predictiva NO mejora al migrar a temporalidades mayores:**
   El resultado fundamental del Ciclo 5 responde directamente a la pregunta planteada por el cliente: **alejarse de M5 hacia H1 o H4 NO incrementa la capacidad discriminativa del modelo.** El ROC-AUC Out-Of-Sample en H1 (**0.5148**) y en H4 (**0.5268**) permanece colindante con el azar puro ($0.5000$).

2. **Efecto de la reducción de costos vs. escasez muestral:**
   Es verdad que en H1 y H4 la fricción del spread y la comisión representa un porcentaje menor del rango típico de las velas. Sin embargo, debido a que el modelo no tiene capacidad real de predecir la dirección futura ($AUC_{OOS} \approx 0.51$), las pocas señales generadas responden únicamente a variaciones aleatorias. En H1 OOS a $Th=0.55$, el Profit Factor ilusorio de $1.75$ se debe a una muestra de solo **21 trades en 22 meses** ($< 1$ trade por mes), lo cual carece por completo de significancia estadística.

3. **Inoperancia en H4 por compresión de probabilidades:**
   En H4, la reducida cantidad de muestras y la baja relación señal/ruido fuerzan al regulador L2 a fijar un peso insignificante para todas las variables. Las probabilidades generadas nunca alcanzan los umbrales de decisión estándar en OOS, resultando en **0 operaciones**.

4. **Veredicto Final e Implicación para el Proyecto:**
   Queda empíricamente demostrado que el problema **no es ni la frecuencia temporal (M5 vs H1 vs H4) ni la arquitectura del modelo (Bayesiano vs Regresión Logística)**. Los indicadores técnicos clásicos derivados exclusivamente del precio pasado OHLC de XAUUSD **carecen de contenido informativo útil sobre el retorno futuro**.

   Para alcanzar una expectativa matemática positiva real en el trading de oro al contado (XAUUSD), **es indispensable abandonar la búsqueda de señales sobre indicadores técnicos de precio e incorporar fuentes de datos primarias externas**, tales como:
   - **Datos Macroeconómicos:** Sorpresas en NFP, CPI, decisiones de la FED y PMI.
   - **Métricas de Microestructura:** Flujo de órdenes (Order Flow), desbalance de agresión y liquidez del DOM.
   - **Variables Cross-Asset:** Rendimiento real de bonos de EE.UU. (US10Y / TIP) e índice DXY.
