# NOTAS_DATOS.md - Registro de Ticks Reales Dukascopy

## Estado Actual de los Ticks Guardados en Git

- **Mes descargado:** Enero 2024 (2024-01-01 a 2024-01-31)
- **Archivo persistido:** `datos/ticks_dukascopy/xauusd_ticks_2024_01.csv.gz`
- **Formato:** CSV comprimido en `.gz` para optimizar almacenamiento en Git
- **Total de Ticks:** 2,933,290
- **Rango de Fechas Real:** `2024-01-01 23:00:00.312` a `2024-01-31 23:59:58.924`
- **Tamaño en Disco:** 20.86 MB
- **Columnas:** `timestamp`, `bid`, `ask`, `volume`
- **Limpieza de Datos:** Se verificó la ausencia de valores inválidos (`bid <= 0` o `ask < bid`). 0 ticks corruptos detectados.
