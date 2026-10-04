# Actividad 4 — Lab4 RF

VLAN 100 estática, DHCP solo en VLAN 200, Internet bloqueado y enrutamiento inter-VLAN permitido en ambos sentidos.

Ejecuta desde **server4 como ubuntu**, situado en la raíz del repositorio. Conserva `DEV/comun/` y `scripts_IP/`: el punto de entrada los necesita. Lee el `readme.md` de la raíz para preparar SSH y dependencias.

## Revisar

```bash
bash DEV/actividad_4/actividad4.sh plan
```

## Desplegar, si el plan terminó correctamente

```bash
bash DEV/actividad_4/actividad4.sh deploy
echo "Codigo de salida: $?"
```

`deploy` limpia los recursos identificados de la topología anterior en server1–3 y crea este escenario. Guarda las evidencias anteriores antes de cambiar de actividad. Los discos gestionados anteriores se conservan en los respaldos de cada nodo.

## Verificar sin recrear

```bash
bash DEV/actividad_4/actividad4.sh verify
```

Marcadores esperados: `DHCP_LAYOUT_OK; ENRUTAMIENTO_INTERVLAN_OK; INTERNET_BLOQUEADO_OK; ENRUTAMIENTO_BIDIRECCIONAL_CON_CONTADORES_OK` y un `PASS` final, con código de salida 0. Los fallos previstos de ping en los escenarios aislados se procesan dentro del script; no son un error global si cumplen la política esperada.

Los registros se guardan en `DEV/actividad_4/evidencias/FECHA-PID/`. Adjunta capturas reales y registros de tu ejecución. Las pruebas incluidas en `DEV/comun/tests/` son simuladas y no sustituyen estas evidencias.

Para retirar el escenario sin desplegar otro: `bash DEV/actividad_4/actividad4.sh clean`.
