# Ciclo 1: Baseline (Parámetros por defecto de fábrica)

## Descripción y Configuración
- **Símbolo**: XAUUSD
- **Timeframe**: M5
- **Período Total**: 2019-01-01 a 2024-12-31 (~5 años)
- **Fuente de Datos**: HuggingFace (`ZombitX64/xauusd-gold-price-historical-data-2004-2025`)
- **Supuestos de Mercado**:
  - Spread: 30 puntos ($0.30 / oz de oro)
  - Comisión: $3.50 USD por lote completo (round turn)
- **División de Datos**:
  - In-Sample (IS - 70%): 2019-01-02 a 2023-03-20 (296130 velas M5)
  - Out-Of-Sample (OOS - 30%): 2023-03-20 a 2024-12-31 (126914 velas M5)

## Resultados Métricas Baseline

| Métrica | In-Sample (IS 70%) | Out-Of-Sample (OOS 30%) |
| :--- | :---: | :---: |
| **Operaciones** | 2041 | 736 |
| **Ganancia Neta ($)** | $-12235.34 | $-10009.26 |
| **Profit Factor (PF)** | 0.73 | 0.6 |
| **Win Rate (%)** | 35.18% | 39.13% |
| **Max Drawdown (%)** | 113.96% | 101.47% |
| **Sharpe Ratio** | 0.01 | 0.0 |
| **Score OnTester** | 0.0 | 0.0 |

## Instrucciones para ejecutar
Para reproducir la prueba baseline:
```bash
python3 scripts/run_ciclo1.py
```
