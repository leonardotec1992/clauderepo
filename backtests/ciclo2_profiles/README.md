# Ciclo 2: Backtest Comparativo de los 4 Perfiles de Riesgo

## Metodología
- **Símbolo**: XAUUSD (Oro) | **Timeframe**: M5
- **Período Total**: 2019-01-01 a 2024-12-31 (~5 años, 423,044 velas M5)
- **Fuente de Datos**: HuggingFace (`ZombitX64/xauusd-gold-price-historical-data-2004-2025`)
- **Balance Inicial**: $10,000 USD
- **Fricciones de Mercado**:
  - Spread: 30 puntos ($0.30 / oz de oro)
  - Comisión: $3.50 USD por lote completo (round turn)
- **División Cronológica de Datos**:
  - **In-Sample (IS - 70%)**: 2019-01-02 a 2023-03-20 (296,130 velas M5)
  - **Out-Of-Sample (OOS - 30%)**: 2023-03-20 a 2024-12-31 (126,914 velas M5)
- **Mecanismos Auditados y Fieles al `.mq5`**:
  - Aplicación exacta de la función `ApplyProfile()` para la configuración de cada perfil (`g_shieldMax`, `g_riskPct`, `g_useLayers`, `g_maxLayers`, `g_usePercent`, `g_objetivoPct`, `g_bePct`).
  - Martingala direccional (layering) según `Layer_Multiplier`, `LayerStepATR`, `LayerLotFactor` y distancia acumulada desde el precio de la última entrada.
  - Gestión rigurosa de Stop-Out / Margin Call que detiene las operaciones forzosamente si `balance <= 0` o `equity <= 0`, evitando operativas fantasmas y saldos negativos.

---

## Tabla Comparativa Única (4 Perfiles x IS / OOS)

| Perfil de Riesgo | Período | Operaciones | Ganancia Neta ($) | Ganancia Neta (%) | Profit Factor (PF) | Win Rate (%) | Max Drawdown (%) | Max Drawdown ($) | Sharpe Ratio | Score OnTester |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **MANUAL** | IS (70%) | 417 | -$10,003.08 | -100.03% | 0.74 | 36.69% | 100.0% | $15,186.48 | -0.09 | 0.0 |
| **MANUAL** | OOS (30%) | 445 | -$10,001.07 | -100.01% | 0.58 | 34.83% | 100.0% | $10,000.00 | -0.11 | 0.0 |
| **CONSERVADOR** | IS (70%) | 2,968 | -$8,921.04 | -89.21% | 0.78 | 37.06% | 89.92% | $9,323.72 | -0.18 | 0.0 |
| **CONSERVADOR** | OOS (30%) | 1,463 | -$6,432.51 | -64.33% | 0.74 | 38.89% | 64.97% | $6,562.78 | -0.19 | 0.0 |
| **BALANCEADO** | IS (70%) | 2,495 | -$9,862.25 | -98.62% | 0.78 | 34.67% | 98.82% | $10,625.14 | -0.18 | 0.0 |
| **BALANCEADO** | OOS (30%) | 1,242 | -$8,231.97 | -82.32% | 0.73 | 37.36% | 82.95% | $8,455.74 | -0.17 | 0.0 |
| **AGRESIVO** | IS (70%) | 1,618 | -$10,000.21 | -100.0% | 0.77 | 34.05% | 100.0% | $11,356.66 | -0.17 | 0.0 |
| **AGRESIVO** | OOS (30%) | 1,136 | -$9,305.87 | -93.06% | 0.72 | 37.41% | 93.61% | $9,899.61 | -0.14 | 0.0 |

---

## Análisis Crítico Honesto y Evaluación de Riesgo

### 1. Evaluación del Riesgo por Perfil
- **MANUAL**: Utiliza el dimensionamiento por interés compuesto de fábrica (`StartingLots = 0.03` por cada $100 USD de balance). En una cuenta de $10,000 USD, abre operaciones de **3.00 lotes** (300 oz de oro). Este sobre-apalancamiento causa la pérdida total del capital (100% Stop-Out / Margin Call) tanto en In-Sample como en Out-Of-Sample tras unas pocas operaciones en racha negativa.
- **AGRESIVO** (`g_riskPct = 1.8%`, `g_maxLayers = 15`): La combinación de un alto porcentaje de riesgo por operación con un límite de hasta 15 capas de martingala direccional acumula una exposición catastrófica en tendencias prolongadas en contra. Quiebra la cuenta en IS (100% DD, -$10,000.21) y sufre un drawdown masivo del 93.61% en OOS.
- **BALANCEADO** (`g_riskPct = 1.0%`, `g_maxLayers = 10`): Aunque reduce el riesgo unitario respecto a Agresivo, permitir hasta 10 capas sigue generando drawdowns inaceptables cerca del margen de quiebra (98.82% en IS y 82.95% en OOS).
- **CONSERVADOR** (`g_riskPct = 0.5%`, `g_maxLayers = 6`): Es el único perfil en el que la cuenta no sufre un Stop-Out del 100%. Sin embargo, experimenta drawdowns severos del 89.92% en IS y 64.97% en OOS debido a que la lógica de señal bayesiana tiene una esperanza matemática negativa (Profit Factor < 1.0).

### 2. Cumplimiento de Criterios de Validación IS / OOS
- **Ratio Profit Factor (PF_OOS ≥ 0.6 × PF_IS)**:
  - MANUAL: 0.58 ≥ 0.444 (Cumple ratio)
  - CONSERVADOR: 0.74 ≥ 0.468 (Cumple ratio)
  - BALANCEADO: 0.73 ≥ 0.468 (Cumple ratio)
  - AGRESIVO: 0.72 ≥ 0.462 (Cumple ratio)
- **Ratio Drawdown (DD_OOS ≤ 1.5 × DD_IS)**:
  - Todos los perfiles cumplen nominalmente la relación de drawdown entre IS y OOS.

### 3. Evaluacion del Piso de Aceptación OnTester
**Declaración Explícita**: **NINGUNO** de los 4 perfiles de riesgo logra superar el piso de aceptación de la función `OnTester()` propia del robot (requiere `operaciones ≥ 40`, `ganancia_neta > 0`, `Profit Factor ≥ 1.15`, `Max Drawdown ≤ 25%`).
Todos los perfiles obtienen un **Score OnTester = 0.0** en IS y OOS debido a que todos registran pérdidas netas, PF entre 0.58 y 0.78, y Drawdowns superiores al 64%.

---

## Recomendación Razonada para la Siguiente Fase

Dado que ningún perfil es rentable bajo la lógica actual de señales de trading, **se recomienda seleccionar el perfil CONSERVADOR** como la base de trabajo para la siguiente fase (Optimización del Motor de Señales):

1. **Razón**: El perfil CONSERVADOR acota el riesgo mediante `g_riskPct = 0.5%` y limita las capas de layering a un máximo de `6`. Es el único perfil que preserva capital sin caer en un Stop-Out del 100%, proveyendo la muestra más amplia y limpia de operaciones (2,968 en IS y 1,463 en OOS) para evaluar mejoras en las señales.
2. **Advertencia de Riesgo de Ruina**: Ninguno de los perfiles actuales es apto para operar en cuentas reales. El problema fundamental no es solo el dimensionamiento de lote o el layering, sino que el motor de señales bayesiano (`ComputePosteriorUp` con RSI/CCI) carece de ventaja estadística (*edge*) en el mercado actual de XAUUSD M5.

---

## Instrucciones de Reproducción

Para ejecutar nuevamente la comparativa completa de los 4 perfiles y generar los gráficos y archivos CSV:
```bash
python3 scripts/run_ciclo2_profiles.py
```
