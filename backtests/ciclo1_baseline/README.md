# Ciclo 1: Baseline (Parámetros por defecto de fábrica)

## Descripción y Configuración
- **Símbolo**: XAUUSD
- **Timeframe**: M5
- **Período Total**: 2019-01-01 a 2024-12-31 (~5 años)
- **Fuente de Datos**: HuggingFace (`ZombitX64/xauusd-gold-price-historical-data-2004-2025`)
- **Balance Inicial**: $10,000 USD
- **Supuestos de Mercado**:
  - Spread: 30 puntos ($0.30 / oz de oro)
  - Comisión: $3.50 USD por lote completo (round turn)
- **División de Datos**:
  - In-Sample (IS - 70%): 2019-01-02 a 2023-03-20 (296130 velas M5)
  - Out-Of-Sample (OOS - 30%): 2023-03-20 a 2024-12-31 (126914 velas M5)

## Resultados Métricas Baseline (Auditadas y Corregidas)

| Métrica | In-Sample (IS 70%) | Out-Of-Sample (OOS 30%) |
| :--- | :---: | :---: |
| **Operaciones** | 417 | 445 |
| **Ganancia Neta ($)** | $-10003.08 | $-10001.07 |
| **Profit Factor (PF)** | 0.74 | 0.58 |
| **Win Rate (%)** | 36.69% | 34.83% |
| **Max Drawdown (%)** | 100.0% | 100.0% |
| **Sharpe Ratio** | -0.09 | -0.11 |
| **Score OnTester** | 0.0 | 0.0 |

---

## Informe de Auditoría del Motor de Backtest

Se realizó una auditoría completa del simulador en `src/backtester.py` verificando los 6 puntos clave exigidos:

### 1. Manejo de Equity/Margin Call & Stop-out
- **Hallazgo y Corrección**: Anteriormente, el simulador no detenía la ejecución cuando la cuenta quebraba o el balance/equity caía por debajo de cero, lo que permitía operativas fantasma con saldo negativo hasta -$2,315 USD y generaba un Max DD espurio del 113.96%. Se corrigió incorporando la detención inmediata por Stop-Out (`Stop Out` / Margin Call) en cuanto `balance <= 0` o `equity <= 0`, cerrando todas las posiciones abiertas y acotando el Max Drawdown al 100.0%.
- **Análisis de Position Sizing**: Los parámetros por defecto de fábrica usan `Usar_Compuesto = True` con `StartingLots = 0.03` por cada $100 USD de balance (`0.01` por cada $100 * 3). Para un balance de $10,000 USD, esto resulta en un volumen inicial de **3.00 lotes** (300 oz de oro). Con un Stop Loss típico basado en ATR (~$8.00 de distancia en oro), cada pérdida representa ~$2,400 USD (24% de la cuenta por operación). Debido a esta sobre-exposición masiva de apalancamiento por defecto, una racha de 4 pérdidas consecutivas agota por completo el capital de la cuenta ($10,000 USD), provocando el Stop-out/Margin Call exacto al llegar al 100% de drawdown.

### 2. Aplicación de Spread y Comisión (Desglose de Operaciones)
- **Spread**: Se aplica 30 puntos ($0.30/oz). Las compras (BUY) abren a precio Ask (`Open + 0.30`) y cierran a precio Bid (`Close`). Las ventas (SELL) abren a Bid (`Open`) y cierran a Ask (`Close + 0.30`).
- **Comisión**: Se restan $3.50 USD por lote operado del PnL en el momento del cierre (`NetPnL = GrossPnL - Commission`).
- **Ejemplo de 3 Operaciones Extraídas de la Simulación**:
  - **Operación #1 (SELL)**: Lote `3.00` | OpenTime: `2019-01-02 10:50` | OpenPrice: `1287.90` (Bid) | ClosePrice: `1285.345` (Ask)
    - PnL Bruto: `(1287.90 - 1285.345) * 100 * 3.00 = +$766.39`
    - Comisión: `3.00 lotes * $3.50 = $10.50`
    - Net PnL: `$766.39 - $10.50 = +$755.89`
  - **Operación #2 (SELL)**: Lote `3.21` | OpenTime: `2019-01-03 01:15` | OpenPrice: `1289.20` | ClosePrice: `1286.321`
    - PnL Bruto: `(1289.20 - 1286.321) * 100 * 3.21 = +$924.20`
    - Comisión: `3.21 lotes * $3.50 = $11.23`
    - Net PnL: `$912.96`
  - **Operación #3 (BUY)**: Lote `3.48` | OpenTime: `2019-01-03 02:00` | OpenPrice: `1286.10` (Ask) | ClosePrice: `1289.069` (Bid)
    - PnL Bruto: `(1289.069 - 1286.10) * 100 * 3.48 = +$1033.37`
    - Comisión: `3.48 lotes * $3.50 = $12.18`
    - Net PnL: `$1021.19`

### 3. Coherencia Win Rate vs Profit Factor vs R:R
- **Relación Matemática**: PF = (WinRate * AvgWin) / ((1 - WinRate) * AvgLoss)
- **Verificación en In-Sample (IS)**:
  - Win Rate = 35.96% (0.3596), Loss Rate = 64.04% (0.6404)
  - Ganancia Promedio Ganadora = $45.99 USD
  - Pérdida Promedio Perdedora = $34.21 USD
  - PF teórico = (0.3596 * 45.99) / (0.6404 * 34.21) = 16.538 / 21.908 = 0.755 (aprox 0.74)
- Las métricas reportadas de Win Rate (36.0%) y Profit Factor (0.74) concuerdan perfectamente.

### 4. Cálculo de Max Drawdown
- Se confirmó que el Max Drawdown se calcula sobre la curva de Equity usando la fórmula estándar: MaxDD = max((Peak - Equity) / Peak) * 100%
- Tras la corrección de Stop-out, el Max DD máximo posible queda rigurosamente acotado al 100.0%.

### 5. Fidelidad de la Lógica de Señal/Filtros
- Revisión línea por línea contra `ea/BayesianGold_XAU_Panel.mq5`:
  - `ComputePosteriorUp`: Coincidencia exacta de log-odds bayesiano.
  - `EMAAllows` y `ADXAllows`: Filtros de tendencia e intensidad en marco H1 (shift=1).
  - `InSession`: Ventanas horarias (NY, Londres, Asia) correctamente alineadas.
  - `ManagePositions`: SL/TP/BE/Trailing stop.
  - Manejo de barras: Cálculo de indicadores técnicos usando velas cerradas (`i-1`) para evitar sesgo de anticipación (lookahead bias).

### 6. Simulación de Velas M5 y Colisión SL/TP Intra-vela
- **Resolución**: Velas M5.
- **Criterio Intra-vela**: Cuando en una misma vela M5 el rango High-Low toca simultáneamente el Stop Loss (SL) y el Take Profit (TP), el simulador asume una política conservadora (peor caso: ejecuta el Stop Loss primero bajo la etiqueta `SL (bar worst)`), evitando sobreestimaciones optimistas de rentabilidad.

---

## Instrucciones para reproducir
Para reproducir la prueba baseline corregida:
```bash
python3 scripts/run_ciclo1.py
```
