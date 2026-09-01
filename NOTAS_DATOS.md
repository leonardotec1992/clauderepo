# NOTAS_DATOS.md - Estado de los Datos de Ticks

## Diagnóstico del Archivo de Ticks

- **Ruta esperada:** `datos/ticks_dukascopy/xauusd-tick-2024-01-01-2024-07-01.csv`
- **Estado en esta nueva sesión:** **NO ENCONTRADO** (El directorio `datos/` no existe en el contenedor de la nueva sesión).
- **Causa:** Al reiniciarse la sesión anterior tras el bloqueo, el almacenamiento efímero del contenedor restauró únicamente los archivos rastreados por Git. Dado que el archivo de ticks de 6 meses no fue subido a Git en la sesión previa, no persiste en la sesión actual.

## Acciones Requeridas
Debido a la instrucción explícita: `"MUY IMPORTANTE: NO descargues datos nuevos de Dukascopy"` y `"Sé honesto: si algo del archivo no sirve o falta, dilo claramente"`, se reporta este estado para recibir instrucciones sobre cómo proceder (por ejemplo, autorizar la descarga controlada de los ticks en bloques pequeños o indicar una fuente alternativa).
