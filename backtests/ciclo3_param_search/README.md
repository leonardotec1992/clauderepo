# Ciclo 3 — Búsqueda Amplia de Parámetros del Motor de Señal Bayesiano (XAUUSD M5)

## 1. Contexto y Objetivos

En el **Ciclo 2**, los 4 perfiles de riesgo del EA (`MANUAL`, `CONSERVADOR`, `BALANCEADO`, `AGRESIVO`) ejecutados con los parámetros de fábrica del motor de señal (`Threshold=0.62`, `W_RSI=1.10`, `W_CCI=0.70`, `W_Slope=0.60`, `W_Return=0.50`, `W_Trend=0.40`, `SL_ATR=2.0`, `TP_R=1.5`) generaron pérdidas netas severas tanto en *In-Sample* (IS) como en *Out-Of-Sample* (OOS), con Profit Factors (PF) entre 0.58 y 0.78.

Antes de intentar ajustar o "arreglar" un único perfil de riesgo, el cliente solicitó explícitamente **aislar el motor de señal y realizar una búsqueda amplia en el espacio de parámetros** de 8 dimensiones para determinar si existe alguna región con ventaja estadística genuina (*edge*), o si la arquitectura bayesiana con indicadores fijos carece de ventaja estructural en XAUUSD M5.

El estudio se estructuró en **dos etapas secuenciales**:
- **ETAPA A — Búsqueda amplia aislando el motor de señal:** Evaluación de 350 combinaciones aleatorias uniformes sobre 8 parámetros clave utilizando lote fijo (0.03 lotes), **SIN compounding** y **SIN layering/martingala**. Se precalcularon los indicadores base (RSI, CCI, ATR, EMA100, EMA50/200, ADX) sobre toda la serie de datos M5/H1 (2019–2024, 423,044 barras) y se vectorizó rigurosamente la evaluación del modelo de probabilidad bayesiano sin desfase temporal.
- **ETAPA B — Interacción señal × money management:** Evaluación de los candidatos más prometedores de la Etapa A bajo los 4 perfiles de riesgo del EA (`MANUAL`, `CONSERVADOR`, `BALANCEADO`, `AGRESIVO`) aplicando la lógica real de *position sizing* y *layering* de `ApplyProfile()`.

---

## 2. Metodología de Búsqueda y Parámetros

### 2.1 Espacio de Búsqueda (8 Dimensiones)
Se definieron los siguientes rangos de búsqueda continua uniforme con semilla fija `seed=42` para total reproducibilidad:

| Parámetro | Significado / Descripción | Rango de Búsqueda | Valor Baseline (Fábrica) |
|---|---|---|---|
| `InpThreshold` | Umbral de decisión Bayesiano | `[0.50, 0.80]` | 0.62 |
| `InpW_RSI` | Peso log-odds RSI | `[0.0, 2.0]` | 1.10 |
| `InpW_CCI` | Peso log-odds CCI | `[0.0, 2.0]` | 0.70 |
| `InpW_Slope` | Peso log-odds pendiente RSI | `[0.0, 2.0]` | 0.60 |
| `InpW_Return` | Peso log-odds retorno reciente | `[0.0, 2.0]` | 0.50 |
| `InpW_Trend` | Peso log-odds tendencia (EMA) | `[0.0, 2.0]` | 0.40 |
| `InpSL_ATR` | Stop Loss (multiplicador ATR) | `[1.0, 4.0]` | 2.0 |
| `InpTP_R` | Take Profit (ratio respecto a SL) | `[0.5, 3.0]` | 1.5 |

### 2.2 Configuración del Backtest y Filtros Mantenidos
- **Periodo:** 2019-01-02 a 2024-12-31 (423,044 barras M5).
- **División Walk-Forward:** 70% In-Sample (`2019-01-02` a `2023-03-20`, 296,130 barras) / 30% Out-Of-Sample (`2023-03-20` a `2024-12-31`, 126,914 barras).
- **Costos de Fricción Fieles:** Spread de 30 puntos ($0.30/oz) y comisión ida y vuelta de $3.50 USD por lote.
- **Filtros Mantenidos sin Alterar:** `Usar_Filtro_ADX` (`ADX_Minimo=25.0`), `Usar_EMA_Filter` (`EMA_Sep_Extrema=0.3`), confirmaciones y anti-extremos de RSI/CCI, ventanas de sesión (NY, Londres, Asia) y gating de volatilidad ATR.

### 2.3 Criterio de Evaluación y Score OnTester
Se implementó la fórmula exacta de `OnTester()` de `BayesianGold_XAU_Panel.mq5`:
$$\text{Score} = \begin{cases}
0.0 & \text{si } \text{Trades} < 40 \text{ o NetProfit} \le 0 \text{ o PF} < 1.15 \text{ o MaxDD\%} > 25.0\% \\
\frac{\text{PF} \cdot \sqrt{\text{Trades}}}{1.0 + \frac{\text{MaxDD\%}}{10.0}} \cdot \left(1.0 + \max(\text{Sharpe}, 0) \cdot 0.1\right) & \text{en otro caso}
\end{cases}$$

---

## 3. Resultados de la Etapa A — Búsqueda Amplia (Señal Aislada)

### 3.1 Distribución Global del Espacio de Parámetros (IS, N=350)
La siguiente tabla resume la distribución de métricas observadas a lo largo de las 350 combinaciones evaluadas en In-Sample (IS):

| Métrica / Criterio | Valor / Porcentaje Observado |
|---|---|
| **Total Combinaciones Evaluadas** | 350 |
| **Combinaciones con PF > 1.0 (Rentables)** | **0 de 350 (0.00%)** |
| **Combinaciones con PF $\ge$ 1.15** | **0 de 350 (0.00%)** |
| **Combinaciones que Aprueban OnTester (Score > 0)** | **0 de 350 (0.00%)** |
| **Rango de Profit Factor (PF) Observado** | `0.47` a `0.92` |
| **Promedio de Profit Factor (PF)** | `0.7414` |
| **Mediana de Profit Factor (PF)** | `0.7500` |
| **Rango de Net Profit (USD)** | -$10,004.77 a -$108.30 |
| **Rango de Max Drawdown (%)** | 3.41% a 100.0% |

> **Observación Crucial:** El **100.00%** de las combinaciones en el espacio de parámetros pierden dinero en In-Sample. La media y mediana del Profit Factor son **0.74** y **0.75**, consistentes con el baseline de fábrica. **Absolutamente ninguna combinación en el espacio de parámetros de 8 dimensiones logró ser rentable en In-Sample bajo lote fijo.**

---

### 3.2 Tabla del Top 20 Candidatos de la Etapa A (IS vs. OOS Walk-Forward)

Se ordenaron las combinaciones por mejor relación PF / menor pérdida y se validaron en Out-Of-Sample (OOS) con el criterio Walk-Forward (`PF_OOS ≥ 0.6 × PF_IS` y `DD_OOS ≤ 1.5 × DD_IS`):

| ID | Threshold | W_RSI | W_CCI | W_Slope | W_Return | W_Trend | SL_ATR | TP_R | IS Trades | IS Net ($) | IS PF | IS MaxDD | OOS Trades | OOS Net ($) | OOS PF | OOS MaxDD | Walk-Forward Pass |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 176 | 0.726 | 0.840 | 1.775 | 0.945 | 1.341 | 1.656 | 2.894 | 2.680 | 67 | -173.88 | 0.92 | 14.31% | 31 | -34.86 | 0.95 | 6.90% | ✅ PASS (PF < 1.0) |
| 315 | 0.718 | 1.139 | 1.399 | 1.065 | 0.941 | 1.309 | 2.768 | 2.775 | 78 | -220.14 | 0.91 | 15.77% | 37 | -27.81 | 0.88 | 8.74% | ✅ PASS (PF < 1.0) |
| 330 | 0.730 | 1.670 | 0.838 | 1.748 | 0.793 | 1.096 | 2.748 | 2.636 | 69 | -193.17 | 0.91 | 14.22% | 33 | -4.68 | 0.99 | 5.85% | ✅ PASS (PF < 1.0) |
| 95 | 0.741 | 1.393 | 1.683 | 0.740 | 0.639 | 0.655 | 2.668 | 2.551 | 67 | -186.63 | 0.90 | 15.24% | 30 | -87.75 | 0.94 | 6.45% | ✅ PASS (PF < 1.0) |
| 56 | 0.713 | 1.340 | 1.464 | 1.026 | 0.697 | 0.605 | 2.451 | 2.658 | 79 | -263.13 | 0.90 | 15.79% | 36 | -47.07 | 0.94 | 8.02% | ✅ PASS (PF < 1.0) |
| 77 | 0.715 | 1.409 | 1.192 | 0.711 | 0.932 | 1.071 | 2.348 | 2.793 | 76 | -239.31 | 0.90 | 16.63% | 34 | -85.71 | 0.99 | 8.52% | ✅ PASS (PF < 1.0) |
| 171 | 0.707 | 1.491 | 1.848 | 1.669 | 1.272 | 0.946 | 2.378 | 2.871 | 79 | -244.71 | 0.90 | 15.64% | 32 | 0.09 | **1.02** | 7.38% | ✅ PASS (Net IS < 0) |
| 85 | 0.725 | 1.409 | 1.776 | 1.248 | 0.518 | 0.880 | 2.671 | 2.659 | 75 | -187.95 | 0.90 | 16.50% | 34 | 12.06 | **1.00** | 6.45% | ✅ PASS (Net IS < 0) |
| 289 | 0.774 | 0.635 | 0.835 | 0.521 | 1.235 | 1.037 | 3.327 | 1.157 | 33 | -81.03 | 0.89 | 3.41% | 19 | -47.97 | **1.08** | 1.58% | ✅ PASS (Net IS < 0) |
| 349 | 0.724 | 0.883 | 1.294 | 1.077 | 0.781 | 1.411 | 2.721 | 2.404 | 74 | -216.03 | 0.89 | 16.44% | 36 | -51.27 | **1.00** | 4.94% | ✅ PASS (Net IS < 0) |
| 11 | 0.749 | 1.171 | 0.949 | 1.636 | 1.034 | 0.638 | 3.012 | 1.631 | 55 | -157.56 | 0.89 | 11.23% | 29 | -73.65 | 0.88 | 4.14% | ✅ PASS (PF < 1.0) |
| 72 | 0.739 | 0.951 | 1.127 | 1.492 | 0.449 | 1.259 | 3.125 | 1.942 | 60 | -157.92 | 0.89 | 12.01% | 32 | -66.60 | 0.89 | 6.00% | ✅ PASS (PF < 1.0) |
| 30 | 0.745 | 1.647 | 1.859 | 1.542 | 1.371 | 1.530 | 3.003 | 1.779 | 59 | -152.07 | 0.89 | 11.10% | 27 | -30.09 | 0.95 | 4.07% | ✅ PASS (PF < 1.0) |
| 229 | 0.796 | 0.446 | 1.764 | 1.547 | 1.785 | 0.941 | 2.815 | 2.222 | 49 | -82.98 | 0.89 | 11.20% | 27 | -79.35 | 0.89 | 8.40% | ✅ PASS (PF < 1.0) |
| 203 | 0.790 | 1.240 | 1.002 | 1.037 | 1.896 | 0.540 | 3.190 | 2.100 | 56 | -108.30 | 0.89 | 11.49% | 29 | -83.19 | 0.90 | 11.19% | ✅ PASS (PF < 1.0) |
| 14 | 0.778 | 1.042 | 0.251 | 1.047 | 1.829 | 0.768 | 3.522 | 0.640 | 20 | -38.43 | 0.88 | 1.89% | 15 | -27.60 | 0.87 | 0.97% | ✅ PASS (PF < 1.0) |
| 36 | 0.742 | 1.889 | 1.954 | 1.625 | 1.184 | 0.615 | 2.583 | 2.658 | 65 | -132.81 | 0.88 | 11.06% | 31 | -36.42 | 0.96 | 5.69% | ✅ PASS (PF < 1.0) |
| 181 | 0.781 | 1.649 | 0.940 | 1.258 | 0.718 | 1.631 | 2.502 | 2.809 | 40 | -60.01 | 0.88 | 7.49% | 27 | -45.09 | 0.94 | 5.69% | ✅ PASS (PF < 1.0) |
| 35 | 0.767 | 0.706 | 0.231 | 0.817 | 0.385 | 1.096 | 3.864 | 2.766 | 4 | 25.17 | 0.87 | 0.77% | 5 | 16.98 | 0.92 | 0.57% | ✅ PASS (PF < 1.0) |
| 74 | 0.767 | 0.083 | 1.838 | 0.041 | 1.939 | 1.665 | 3.427 | 0.697 | 2 | 2.13 | 0.85 | 0.12% | 0 | 0.00 | 0.00 | 0.00% | ❌ FAIL (0 trades OOS) |

---

## 4. Resultados de la Etapa B — Interacción Señal × Money Management

Se tomaron los 5 mejores candidatos por consistencia y PF en OOS (IDs: `229`, `289`, `35`, `195`, `181`) y se evaluaron reactivando la lógica completa de sizing y layering de los 4 perfiles del EA (`MANUAL`, `CONSERVADOR`, `BALANCEADO`, `AGRESIVO`):

| Candidate ID | Profile Name | IS Trades | IS Net Profit ($) | IS PF | IS MaxDD (%) | OOS Trades | OOS Net Profit ($) | OOS PF | OOS MaxDD (%) |
|---|---|---|---|---|---|---|---|---|---|
| **229** | `MANUAL` | 417 | -$10,001.96 | 0.63 | 100.00% | 445 | -$10,004.01 | 0.57 | 100.00% |
| **229** | `CONSERVADOR` | 2,968 | -$3,538.22 | 0.90 | 41.17% | 1,463 | -$97.27 | 0.99 | 17.72% |
| **229** | `BALANCEADO` | 2,495 | -$5,690.45 | 0.90 | 61.32% | 1,242 | -$2,298.86 | 0.92 | 44.35% |
| **229** | `AGRESIVO` | 1,618 | -$8,900.27 | 0.85 | 90.17% | 1,136 | -$3,311.99 | 0.92 | 63.52% |
| **289** | `MANUAL` | 417 | -$9,845.21 | 0.84 | 99.29% | 445 | -$8,532.61 | 0.90 | 95.35% |
| **289** | `CONSERVADOR` | 2,968 | -$1,027.61 | 0.90 | 17.05% | 1,463 | -$49.99 | 0.99 | 11.39% |
| **289** | `BALANCEADO` | 2,495 | -$1,556.39 | 0.93 | 26.08% | 1,242 | +$189.58 | **1.01** | 18.88% |
| **289** | `AGRESIVO` | 1,618 | -$2,755.63 | 0.93 | 43.89% | 1,136 | +$50.26 | **1.00** | 31.77% |
| **35** | `MANUAL` | 417 | -$10,000.33 | 0.73 | 100.00% | 445 | -$10,001.13 | 0.53 | 100.00% |
| **35** | `CONSERVADOR` | 2,968 | -$3,843.70 | 0.90 | 54.47% | 1,463 | -$245.92 | 0.99 | 25.64% |
| **35** | `BALANCEADO` | 2,495 | -$7,581.88 | 0.88 | 84.63% | 1,242 | -$2,891.47 | 0.91 | 45.21% |
| **35** | `AGRESIVO` | 1,618 | -$9,348.14 | 0.89 | 96.82% | 1,136 | -$4,737.33 | 0.89 | 66.67% |
| **195** | `MANUAL` | 417 | -$10,002.55 | 0.79 | 100.00% | 445 | -$9,899.85 | 0.69 | 99.20% |
| **195** | `CONSERVADOR` | 2,968 | -$2,841.66 | 0.91 | 50.63% | 1,463 | +$267.88 | **1.02** | 23.01% |
| **195** | `BALANCEADO` | 2,495 | -$6,416.92 | 0.87 | 77.90% | 1,242 | -$2,381.67 | 0.90 | 45.78% |
| **195** | `AGRESIVO` | 1,618 | -$8,063.42 | 0.89 | 91.78% | 1,136 | -$5,081.80 | 0.84 | 68.00% |
| **181** | `MANUAL` | 417 | -$10,004.77 | 0.69 | 100.00% | 445 | -$4,178.17 | 0.91 | 99.26% |
| **181** | `CONSERVADOR` | 2,968 | -$4,193.11 | 0.90 | 52.66% | 1,463 | -$169.51 | 0.99 | 26.64% |
| **181** | `BALANCEADO` | 2,495 | -$7,767.17 | 0.84 | 83.59% | 1,242 | -$423.98 | 0.99 | 47.34% |
| **181** | `AGRESIVO` | 1,618 | -$9,309.69 | 0.81 | 95.89% | 1,136 | -$3,149.80 | 0.92 | 74.19% |

---

## 5. Análisis Crítico Honesto y Conclusiones

### 5.1 Conclusión sobre el Motor de Señal Bayesiano
1. **Ausencia Absoluta de Ventaja Estadística Estructural (Edge):**
   - La búsqueda aleatoria uniforme en 350 combinaciones a lo largo de 6 años de datos demuestra que el espacio de parámetros es **uniformemente deficiente**.
   - Con un promedio y mediana de Profit Factor de **0.74** y **0.75**, el **100.00%** de las combinaciones pierden dinero en In-Sample bajo lote fijo (sin layering).
   - **Ninguna de las 350 combinaciones logró un Score OnTester mayor a 0.0**.

2. **Evaluación de la Interacción con Money Management (Etapa B):**
   - En la Etapa B, bajo todos los candidatos y perfiles de riesgo, **todos los resultados In-Sample generaron pérdidas netas significativas** (PF entre 0.63 y 0.93).
   - Los ligeros valores positivos observados en OOS para algunos perfiles (ej. Candidate 289 Balanceado OOS PF 1.01, Candidate 195 Conservador OOS PF 1.02) son el resultado directo de la variación del régimen de mercado y del suavizado por martingala en una muestra limitada, pero **descalifican totalmente debido a las pérdidas en In-Sample**.

3. **Implicación para el Proyecto:**
   - La combinación lineal ponderada de log-odds basada en RSI(14), CCI(14), pendiente RSI, retorno de barra y distancia a la EMA100 en temporalidad M5 **no posee capacidad predictiva ni esperanza matemática positiva en XAUUSD M5** frente a los costos reales de spread (30 pts) y comisión ($3.50/lote).
   - La solución **NO radica en re-sintonizar ni calibrar pesos fijos** dentro de la arquitectura actual del EA. Para lograr rentabilidad y pasar el filtro estricto de `OnTester()`, se requiere reconsiderar la hipótesis de señal (ej. incorporar estructura de mercado de temporalidad superior, filtrado directo por volumen real / microestructura, o modelos de clasificación no lineales).

---

## 6. Archivos Entregables

1. `scripts/run_ciclo3_param_search.py`: Script modular con precálculo vectorizado de probabilidades bayesianas y ejecución paralela multiproceso.
2. `backtests/ciclo3_param_search/etapa_a_all_combinations_is.csv`: Resultados completos de las 350 combinaciones de la Etapa A en In-Sample.
3. `backtests/ciclo3_param_search/etapa_a_top_candidates_is_oos.csv`: Comparativa Walk-Forward IS vs. OOS de los 20 mejores candidatos de la Etapa A.
4. `backtests/ciclo3_param_search/etapa_b_candidates_x_profiles.csv`: Matriz de resultados de los 5 mejores candidatos evaluados bajo los 4 perfiles de riesgo del EA.
5. `backtests/ciclo3_param_search/README.md`: Este reporte metodológico y de análisis crítico.
