# Actividad 3 — Lab4 RF

DHCP en ambas VLAN, Internet bloqueado y comunicación inter-VLAN bloqueada.

Ejecuta desde **server4 como ubuntu**, situado en la raíz del repositorio. Conserva `DEV/comun/` y `scripts_IP/`: el punto de entrada los necesita. Lee el `readme.md` de la raíz para preparar SSH y dependencias.

## Revisar

```bash
bash DEV/actividad_3/actividad3.sh plan
```

## Desplegar, si el plan terminó correctamente

```bash
bash DEV/actividad_3/actividad3.sh deploy
echo "Codigo de salida: $?"
```

`deploy` limpia los recursos identificados de la topología anterior en server1–3 y crea este escenario. Guarda las evidencias anteriores antes de cambiar de actividad. Los discos gestionados anteriores se conservan en los respaldos de cada nodo.

## Verificar sin recrear

```bash
bash DEV/actividad_3/actividad3.sh verify
```

Marcadores esperados: `DHCP; INTERNET_HOST_OK; INTERNET_BLOQUEADO_OK; AISLAMIENTO_OK` y un `PASS` final, con código de salida 0. Los fallos previstos de ping en los escenarios aislados se procesan dentro del script; no son un error global si cumplen la política esperada.

Los registros se guardan en `DEV/actividad_3/evidencias/FECHA-PID/`. Adjunta capturas reales y registros de tu ejecución. Las pruebas incluidas en `DEV/comun/tests/` son simuladas y no sustituyen estas evidencias.

Para retirar el escenario sin desplegar otro: `bash DEV/actividad_3/actividad3.sh clean`.
