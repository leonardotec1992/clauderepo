# Ciclo 6: Incorporación de Variables Macroeconómicas y Cross-Asset (DXY, Tasas US10Y, Plata, Petróleo)

## Contexto y Objetivo

En los Ciclos 1 al 5 se descartó rigurosamente que el problema de rendimiento del EA residiera en:
1. Errores del motor de backtest.
2. Position sizing o configuración de perfiles de riesgo.
3. Pesos del motor probabilístico bayesiano (350 combinaciones probadas, 0% rentables).
4. La arquitectura de combinación de features sobre indicadores de precio (Regresión Logística L2 con 25 features causales dio ROC-AUC $\approx 0.52-0.53$, esencialmente ruido).
5. La temporalidad de ejecución (M5, H1 y H4 dieron todos ROC-AUC OOS entre $0.51$ y $0.526$).

La conclusión explícita del Ciclo 5 fue: *"Es indispensable abandonar la búsqueda de señales sobre indicadores técnicos de precio e incorporar fuentes de datos primarias externas."*

El objetivo del **Ciclo 6** es incorporar variables macroeconómicas y cross-asset como features adicionales, evaluando si las interrelaciones macro/cross-asset agregan contenido predictivo real sobre el precio del oro en la temporalidad H1.

---

## Adquisición de Datos y Alineación Causal

### Fuentes Exactas y Disponibilidad
1. **Índice del Dólar (DXY):** Serie FRED `DTWEXBGS` (Broad U.S. Dollar Index).
   - Rango obtenido: 2018-01-01 a 2024-12-31.
   - Disponibilidad: 100% exitosa vía `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DTWEXBGS`.
2. **Rendimiento del Bono del Tesoro EE.UU. a 10 años (US10Y):** Serie FRED `DGS10`.
   - Rango obtenido: 2018-01-01 a 2024-12-31.
   - Disponibilidad: 100% exitosa vía `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS10`.
3. **Petróleo WTI:** Serie FRED `DCOILWTICO`.
   - Rango obtenido: 2018-01-01 a 2024-12-31.
   - Disponibilidad: 100% exitosa vía `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DCOILWTICO`.
4. **Plata (XAGUSD):** Yahoo Finance serie `SI=F` (Futures Silver).
   - *Nota de alternativa:* Se probó la descarga desde Stooq (`https://stooq.com/q/d/l/?s=xagusd&i=d`), pero devolvió un desafío JavaScript de verificación de navegador (anti-bot challenge). Se utilizó Yahoo Finance `SI=F` como alternativa 100% funcional.

### Regla Estricta de Alineación Causal
Las series macro son diarias. Para eliminar todo sesgo de anticipación (look-ahead bias), se aplicó la siguiente regla:
- Para cualquier vela H1 del oro en la fecha $D$ y hora $H$, **únicamente se utiliza el valor macro cerrado en el día de trading anterior ($D-1$)**.
- Matemáticamente, los datos diarios se desplazaron 1 día (`shift(1)`) y luego se unieron causalmente a las velas intradía del oro usando `pd.merge_asof(..., direction='backward')`.

---

## Features Macro Derivadas

Se derivaron 9 variables macroeconómicas y cross-asset:
- **DXY:** Retorno 1-día (`DXY_ret1`), distancia a MA50 (`DXY_dist_MA50`), distancia a MA200 (`DXY_dist_MA200`), y relación MA50 vs MA200 (`DXY_MA50_vs_MA200`).
- **US10Y:** Nivel actual (`US10Y_level`) y cambio diario (`US10Y_chg1`).
- **Plata (XAGUSD):** Retorno 1-día (`XAG_ret1`) y Ratio Oro/Plata (`Gold_Silver_ratio`).
- **Petróleo WTI:** Retorno 1-día (`WTI_ret1`).

---

## Parte 1: Diagnóstico de Contenido Informativo (In-Sample H1)

Evaluación del **Information Coefficient (IC de Spearman)** y **ROC-AUC** sobre las 24,596 velas H1 de la partición In-Sample (IS: 2019-01-14 a 2023-03-16) para $K=1$ vela:

| Feature | Spearman IC (K=1) | p-value (K=1) | ROC-AUC (K=1) |
| :--- | :---: | :---: | :---: |
| `US10Y_level` | -0.013713 | 3.15e-02 | 0.492920 |
| `DXY_ret1` | 0.009528 | 1.35e-01 | 0.506086 |
| `DXY_dist_MA200` | -0.008197 | 1.99e-01 | 0.496064 |
| `DXY_dist_MA50` | -0.007537 | 2.37e-01 | 0.495336 |
| `DXY_MA50_vs_MA200` | -0.005808 | 3.62e-01 | 0.498000 |
| `Gold_Silver_ratio` | 0.005268 | 4.09e-01 | 0.503229 |
| `XAG_ret1` | -0.004220 | 5.08e-01 | 0.496396 |
| `US10Y_chg1` | -0.003410 | 5.93e-01 | 0.500610 |
| `WTI_ret1` | 0.000717 | 9.11e-01 | 0.499136 |


*Observación Parte 1:* Todos los valores de IC de Spearman se ubican entre $-0.021$ y $+0.020$ con ROC-AUC en el rango $[0.485, 0.518]$. Ninguna variable macro individual muestra un edge lineal o discriminativo significativo por sí sola en la frecuencia H1.

---

## Parte 2: Ajuste de Modelos L2 y Comparación de ROC-AUC

Se ajustaron dos modelos de Regresión Logística L2 con validación cruzada interna en IS:
1. **Modelo Solo-Macro:** Entrenado exclusivamente con las 9 variables macro.
2. **Modelo Combinado (Macro + Técnico):** Entrenado con las 9 variables macro + las 25 variables técnicas de ciclos anteriores.

### Comparación Crítica contra Baselines

| Modelo | Partición IS (ROC-AUC) | Partición OOS (ROC-AUC) | Δ AUC OOS vs Baseline Ciclo 5 |
| :--- | :---: | :---: | :---: |
| **Ciclo 5 Baseline (Solo Técnico H1)** | 0.53305 | 0.51481 | - |
| **Ciclo 6 Solo-Macro (9 features)** | 0.51234 | 0.50291 | -0.01190 |
| **Ciclo 6 Macro + Técnico (34 features)** | 0.53397 | 0.51338 | -0.00143 |

*Conclusión de Capacidad Predictiva:*
El modelo **Solo-Macro** obtiene un AUC Out-Of-Sample de **0.5029**, prácticamente **azar puro (0.5000)**. Al combinar las variables macro con los indicadores técnicos, el AUC OOS alcanza **0.51338**, mostrando un cambio nulo/insignificante respecto al baseline de solo-precio del Ciclo 5 (0.51481). Las variables macro a frecuencia diaria NO agregan capacidad predictiva real para anticipar la dirección del oro a nivel intradía H1.

---

## Parte 3: Resultados de Backtest con Costos Reales (Spread 30pts + Comisión $3.50/lote)

### Backtest In-Sample (IS)
| Model         |   Threshold | Set   |   trades |   net_profit |   net_profit_pct |   profit_factor |   win_rate |   max_dd_pct |   max_dd_usd |   sharpe_ratio |   ontester_score |
|:--------------|------------:|:------|---------:|-------------:|-----------------:|----------------:|-----------:|-------------:|-------------:|---------------:|-----------------:|
| Macro+Tecnico |        0.52 | IS    |      405 |        28.64 |             0.29 |            1.01 |      41.23 |         6.87 |       726.93 |           0.01 |             0    |
| Macro+Tecnico |        0.53 | IS    |      295 |       112.79 |             1.13 |            1.03 |      42.71 |         6.31 |       672.49 |           0.03 |             0    |
| Macro+Tecnico |        0.54 | IS    |      183 |       351.53 |             3.52 |            1.16 |      45.36 |         3.33 |       353.7  |           0.09 |            11.86 |
| Macro+Tecnico |        0.55 | IS    |       86 |      -146.46 |            -1.46 |            0.87 |      38.37 |         4.46 |       460.2  |          -0.06 |             0    |

### Backtest Out-Of-Sample (OOS)
| Model         |   Threshold | Set   |   trades |   net_profit |   net_profit_pct |   profit_factor |   win_rate |   max_dd_pct |   max_dd_usd |   sharpe_ratio |   ontester_score |
|:--------------|------------:|:------|---------:|-------------:|-----------------:|----------------:|-----------:|-------------:|-------------:|---------------:|-----------------:|
| Macro+Tecnico |        0.52 | OOS   |       91 |        -0.38 |            -0    |            1    |      40.66 |         4.54 |       457.06 |           0    |                0 |
| Macro+Tecnico |        0.53 | OOS   |       50 |        94.11 |             0.94 |            1.15 |      44    |         2.56 |       258.1  |           0.07 |                0 |
| Macro+Tecnico |        0.54 | OOS   |       24 |       -66.09 |            -0.66 |            0.82 |      33.33 |         2.72 |       273.09 |          -0.06 |                0 |
| Macro+Tecnico |        0.55 | OOS   |        8 |       -61.02 |            -0.61 |            0.57 |      25    |         1.49 |       148.86 |          -0.11 |                0 |

### Etapa B: Evaluación bajo los 4 Perfiles de Riesgo (Th=0.53)
| Model         |   Profile_ID | Profile_Name   |   Threshold |   IS_Trades |   IS_NetProfit |   IS_PF |   IS_WinRate |   IS_MaxDD |   IS_Sharpe |   IS_OnTester |   OOS_Trades |   OOS_NetProfit |   OOS_PF |   OOS_WinRate |   OOS_MaxDD |   OOS_Sharpe |   OOS_OnTester |
|:--------------|-------------:|:---------------|------------:|------------:|---------------:|--------:|-------------:|-----------:|------------:|--------------:|-------------:|----------------:|---------:|--------------:|------------:|-------------:|---------------:|
| Macro+Tecnico |            0 | MANUAL         |        0.53 |         267 |      -10006.9  |    0.96 |        42.7  |     100    |        0.06 |             0 |           49 |        15688.5  |     1.33 |         53.06 |       87.22 |         0.21 |              0 |
| Macro+Tecnico |            1 | CONSERVADOR    |        0.53 |         329 |        -259.95 |    0.97 |        42.86 |      14.06 |       -0.02 |             0 |           56 |         -145.11 |     0.9  |         41.07 |        6.39 |        -0.04 |              0 |
| Macro+Tecnico |            2 | BALANCEADO     |        0.53 |         325 |         262.14 |    1.01 |        42.15 |      25.51 |        0.02 |             0 |           56 |         -239.02 |     0.92 |         41.07 |       13.29 |        -0.03 |              0 |
| Macro+Tecnico |            3 | AGRESIVO       |        0.53 |         325 |         214.09 |    1.01 |        42.15 |      43.17 |        0.03 |             0 |           56 |         -431.34 |     0.92 |         41.07 |       22.88 |        -0.02 |              0 |

---

## Conclusión Crítica Honesta y Recomendación Final

1. **Veredicto Científico y Empírico:**
   Incorporar series macroeconómicas y cross-asset a frecuencia diaria (DXY, rendimiento US10Y, precio de la plata, petróleo WTI) **NO proporciona ninguna ventaja predictiva ni mejora el ROC-AUC Out-Of-Sample (0.51338 vs 0.51481)**.
2. **Causa Raíz:**
   Las variables macroeconómicas diarias cambian una vez cada 24 horas y reflejan tendencias macro estructurales de largo plazo. Intentar predecir el comportamiento estocástico del oro en velas intradía H1 o M5 con datos diarios causa un descalce insuperable de frecuencias, donde el ruido del microprecio intradía domina totalmente.
3. **Recomendación Definitiva:**
   Tras 6 ciclos de evaluación exhaustiva e independiente (probando bugs, position sizing, combinaciones bayesianas, regresión L2, temporalidades H1/H4 y variables macro/cross-asset), **se confirma que NO existe edge utilizable mediante modelos predictivos basados en indicadores técnicos tradicionales ni series macro diarias**.
   Para encontrar una ventaja competitiva genuina en XAUUSD, se debe abandonar la predicción direccional basada en series de tiempo clásicas y transicionar hacia:
   - Datos de **Microestructura de Mercado de Alta Frecuencia** (Level 2 DOM, Order Flow, Order Book Imbalance y Volume Delta).
   - Eventos macro de impacto instantáneo (**Economic Calendar Event Surprises** / NFP, CPI, FED Rate Decisions en ventanas de segundos/minutos post-noticia).
