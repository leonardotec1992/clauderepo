# Ciclo 4: Rediseño del Motor de Señal

## Contexto y Objetivo
En el Ciclo 3 se demostró que la combinación lineal de los 5 indicadores originales (RSI, CCI, Pendiente RSI, Retorno y Distancia EMA100) no poseía expectativa matemática positiva en XAUUSD M5 frente a los costos reales de transacción (30 pips de spread y $3.50 por lote de comisión).

El objetivo del Ciclo 4 fue rediseñar el motor de señal en dos partes:
1. **Diagnóstico de Contenido Informativo (Parte 1):** Evaluación de la capacidad predictiva individual (Spearman IC y ROC-AUC) de cada feature en ventanas de tiempo In-Sample (IS) a horizontes K=1, K=6 y K=12 barras de M5.
2. **Modelo Ajustado con Features Ampliadas (Parte 2):** Construcción de un feature set ampliado de 25 variables causales (sin look-ahead), entrenamiento de una Regresión Logística con regularización L2 (con tuning interno de $C$ y umbral dentro de IS), y evaluación final en el período Out-Of-Sample (OOS).

---

## Parte 1: Diagnóstico de Contenido Informativo (In-Sample)

Se calcularon el **Information Coefficient (IC de Spearman)** y el **ROC-AUC** sobre las 296,130 barras del período In-Sample (70% cronológico) para cada una de las 25 features frente a la dirección del precio en las siguientes K barras:

### Tabla de IC y AUC por Feature (Top 15 por |IC| en K=1)

| Feature | Categoria | Spearman IC (K=1) | p-value (K=1) | ROC-AUC (K=1) | ROC-AUC (K=6) | ROC-AUC (K=12) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `sReturn` | Original | -0.044134 | 3.74e-127 | 0.4764 | 0.4830 | 0.4851 |
| `RSI_7` | Ampliadas | -0.043252 | 3.38e-122 | 0.4750 | 0.4726 | 0.4720 |
| `sSlope` | Original | -0.040643 | 4.07e-108 | 0.4786 | 0.4853 | 0.4876 |
| `BB_pctB` | Ampliadas | -0.039180 | 1.31e-100 | 0.4771 | 0.4742 | 0.4728 |
| `sRSI` | Original | 0.036517 | 1.23e-87 | 0.5215 | 0.5247 | 0.5255 |
| `RSI` | Ampliadas | -0.036517 | 1.23e-87 | 0.4785 | 0.4753 | 0.4745 |
| `sCCI` | Original | 0.034514 | 1.74e-78 | 0.5203 | 0.5245 | 0.5260 |
| `RSI_21` | Ampliadas | -0.031723 | 1.37e-66 | 0.4813 | 0.4780 | 0.4772 |
| `MACD_hist` | Ampliadas | -0.028243 | 3.75e-53 | 0.4836 | 0.4821 | 0.4812 |
| `sTrend` | Original | -0.019958 | 2.14e-27 | 0.4893 | 0.4850 | 0.4837 |
| `H1_dist_EMA50` | Ampliadas | -0.006841 | 2.02e-04 | 0.4960 | 0.4926 | 0.4918 |
| `ATR_pct_rank` | Ampliadas | 0.005453 | 3.05e-03 | 0.5048 | 0.5050 | 0.5044 |
| `H1_dir_EMA50` | Ampliadas | -0.005170 | 4.97e-03 | 0.4976 | 0.4956 | 0.4959 |
| `BB_bandwidth` | Ampliadas | 0.005056 | 6.02e-03 | 0.5052 | 0.5037 | 0.5032 |
| `ADX` | Ampliadas | 0.004408 | 1.66e-02 | 0.5030 | 0.5044 | 0.5051 |
| `H1_EMA50_vs_EMA200` | Ampliadas | 0.002793 | 1.29e-01 | 0.5017 | 0.5028 | 0.5024 |
| `Day_Mon` | Ampliadas | -0.002246 | 2.22e-01 | 0.4990 | 0.4977 | 0.4953 |
| `Day_Fri` | Ampliadas | 0.002150 | 2.43e-01 | 0.5013 | 0.5025 | 0.5021 |
| `H1_dist_EMA200` | Ampliadas | -0.001890 | 3.04e-01 | 0.4989 | 0.4977 | 0.4970 |
| `Sess_London` | Ampliadas | -0.001858 | 3.13e-01 | 0.4981 | 0.4969 | 0.4952 |
| `Sess_Out` | Ampliadas | 0.001834 | 3.19e-01 | 0.5028 | 0.5032 | 0.5040 |
| `Day_Tue` | Ampliadas | 0.001785 | 3.32e-01 | 0.5009 | 0.5002 | 0.5002 |
| `Day_Thu` | Ampliadas | -0.001276 | 4.88e-01 | 0.4993 | 0.4991 | 0.4998 |
| `Sess_NY` | Ampliadas | 0.001244 | 4.99e-01 | 0.5009 | 0.5017 | 0.5007 |
| `H1_dir_EMA200` | Ampliadas | -0.000974 | 5.97e-01 | 0.4996 | 0.4988 | 0.4991 |
| `Day_Wed` | Ampliadas | -0.000408 | 8.25e-01 | 0.4996 | 0.5004 | 0.5026 |
| `Sess_Asia` | Ampliadas | -0.000022 | 9.90e-01 | 0.4992 | 0.4999 | 0.5008 |

### Hallazgos del Diagnóstico (Parte 1)
- **Extrema debilidad predictiva:** Ninguna feature individual tiene un ROC-AUC significativamente superior a **0.525** o inferior a **0.472**.
- Para K=1 bar (5 min ahead), el mayor IC absoluto es de **-0.044** (`sReturn` y `RSI_7`), con AUCs de **0.476** y **0.475**.
- Las variables de régimen de volatilidad (`ATR_pct_rank`), ADX, distancia H1 a EMAs y dummies de sesión/día muestran AUCs colindantes con el azar puro (**0.495 – 0.505**).

---

## Parte 2: Modelo Ajustado (Regresión Logística L2)

Se ajustó un modelo de Regresión Logística con regularización L2 ($C=0.001$ seleccionado mediante validación interna 70/30 en IS) estandarizando features con `StandardScaler`.

### Coeficientes del Modelo Ajustado

| Feature | Coeficiente ($w$) | Magnitude ($|w|$) |
| :--- | :---: | :---: |
| `RSI_7` | -0.075397 | 0.075397 |
| `sReturn` | -0.048864 | 0.048864 |
| `sCCI` | -0.021693 | 0.021693 |
| `H1_dist_EMA50` | -0.019388 | 0.019388 |
| `sRSI` | 0.014762 | 0.014762 |
| `RSI` | -0.014762 | 0.014762 |
| `H1_dir_EMA50` | 0.013301 | 0.013301 |
| `sTrend` | 0.012380 | 0.012380 |
| `RSI_21` | 0.011338 | 0.011338 |
| `Sess_NY` | 0.010929 | 0.010929 |
| `ATR_pct_rank` | 0.008212 | 0.008212 |
| `H1_EMA50_vs_EMA200` | 0.007980 | 0.007980 |
| `BB_pctB` | 0.007776 | 0.007776 |
| `MACD_hist` | -0.007247 | 0.007247 |
| `BB_bandwidth` | 0.006249 | 0.006249 |
| `H1_dir_EMA200` | 0.005867 | 0.005867 |
| `Day_Fri` | 0.005484 | 0.005484 |
| `Sess_London` | -0.004590 | 0.004590 |
| `Sess_Out` | 0.004538 | 0.004538 |
| `Day_Mon` | -0.004338 | 0.004338 |
| `H1_dist_EMA200` | -0.003884 | 0.003884 |
| `Day_Tue` | 0.003805 | 0.003805 |
| `Day_Thu` | -0.003342 | 0.003342 |
| `ADX` | 0.002968 | 0.002968 |
| `Day_Wed` | -0.001585 | 0.001585 |
| `sSlope` | -0.000965 | 0.000965 |
| `Sess_Asia` | -0.000069 | 0.000069 |

### Métrica de Discriminación del Modelo (AUC)
- **AUC In-Sample (IS):** `0.52968`
- **AUC Out-Of-Sample (OOS):** `0.51601`

---

## Resultados de Backtest (Señal Aislada: Lote Fijo 0.03, SL/TP ATR)

Evaluación del modelo ajustado bajo distintos umbrales de probabilidad en IS (70%) y OOS (30%):

| Threshold | Set | Trades | Net Profit ($) | Profit Factor | Win Rate (%) | Max DD (%) | Sharpe | OnTester |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 0.52 | IS | 3888 | $-6249.06 | 0.69 | 32.95% | 64.01% | -0.28 | 0.00 |
| 0.52 | OOS | 2050 | $-4400.07 | 0.63 | 31.07% | 44.21% | -0.35 | 0.00 |
| 0.53 | IS | 3193 | $-4371.07 | 0.73 | 34.42% | 44.95% | -0.21 | 0.00 |
| 0.53 | OOS | 1681 | $-3478.28 | 0.65 | 31.83% | 35.00% | -0.31 | 0.00 |
| 0.54 | IS | 2371 | $-2491.33 | 0.79 | 36.06% | 25.98% | -0.14 | 0.00 |
| 0.54 | OOS | 1235 | $-1980.74 | 0.72 | 34.41% | 20.16% | -0.21 | 0.00 |
| 0.55 | IS | 1460 | $-1232.10 | 0.83 | 36.99% | 14.55% | -0.08 | 0.00 |
| 0.55 | OOS | 790 | $-1183.92 | 0.75 | 34.30% | 12.05% | -0.15 | 0.00 |

---

## Etapa B: Interacción Señal x Money Management (4 Perfiles de Riesgo)

Evaluación del modelo bajo los 4 perfiles de riesgo con compounding y layering a un umbral $Th = 0.53$:

| Perfil | IS Trades | IS Net Profit ($) | IS PF | IS Max DD (%) | OOS Trades | OOS Net Profit ($) | OOS PF | OOS Max DD (%) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| MANUAL | 468 | $-10000.06 | 0.64 | 100.0% | 210 | $-10000.80 | 0.45 | 100.0% |
| CONSERVADOR | 3374 | $-9048.95 | 0.77 | 91.3% | 1801 | $-8112.25 | 0.66 | 81.5% |
| BALANCEADO | 2945 | $-9916.45 | 0.79 | 99.2% | 1585 | $-9572.39 | 0.59 | 95.9% |
| AGRESIVO | 1989 | $-10001.16 | 0.78 | 100.0% | 1226 | $-9986.97 | 0.51 | 99.9% |

---

## Análisis Crítico Honesto Obligatorio

1. **Ausencia de Contenido Informativo Sustancial:**
   El diagnóstico de la Parte 1 demuestra categóricamente que **ninguna de las 25 features individuales** (tanto las 5 originales como las 20 ampliadas) posee una capacidad predictiva estadísticamente útil sobre la dirección del precio en XAUUSD M5. Los valores de ROC-AUC situados rígidamente en el rango $[0.472, 0.526]$ indican que los indicadores técnicos estándar construidos únicamente a partir de precios e indicadores de M5/H1 equivalen numéricamente a ruido blanco con una desviación ínfima.

2. **Imposibilidad de Edge con Modelos Combinatorios:**
   Al combinar linealmente estas variables mediante un modelo ajustado de Regresión Logística L2, el AUC del modelo combinado alcanza apenas **0.5297 en IS** y decae a **0.5160 en OOS**. Cuando esta señal probabilística se enfrenta a la fricción del mercado real de XAUUSD (30 puntos de spread + $3.50 por lote en comisión), el Profit Factor resultante se sitúa consistentemente entre **0.65 y 0.75** en OOS, generando pérdidas systematicas en todos los umbrales de operación estándar.

3. **Conclusión Fundamental:**
   El problema subyacente en XAUUSD M5 **no es la arquitectura combinatoria** (sea bayesiana, suma ponderada o regresión logística), sino la **fuente de información**. Aplicar más ingeniería de atributos sobre series de precios OHLC en un timeframe intradía de alta frecuencia como M5 no puede superar los costos de transacción en un mercado altamente eficiente como el oro al contado.

4. **Recomendación para Desarrollos Futuros:**
   Para obtener un edge real con expectativa matemática positiva, se requiere cambiar la fuente de datos subyacente hacia inputs no basados puramente en precios pasados de M5, tales como:
   - **Order Flow / Depth of Market (DOM):** Desbalance de libro de órdenes y volumen de agresión.
   - **Datos Macro / Fundamentales:** Sorpresas en indicadores de EE.UU. (CPI, NFP, decisiones de tasa de la FED).
   - **Correlaciones de Activos Cruzados:** Rendimiento de bonos del Tesoro a 10 años (US10Y), índice DXY, e índices bursátiles globales.
   - **Mecanismos de Ejecución Estructurados:** Filtros de régimen de volatilidad con duraciones de trade multibar más amplias o marcos temporales superiores.
