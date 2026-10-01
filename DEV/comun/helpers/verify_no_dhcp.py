#!/usr/bin/env python3
"""No hay DHCP de laboratorio en server3 durante A2; no modifica recursos."""
from pathlib import Path
import sys
# Python con safe-path no siempre incluye el directorio del script.
sys.path.insert(0,str(Path(__file__).resolve().parent))
import cleanup

try:
    plan=cleanup.inventory('server3')
    if plan['errors']:raise RuntimeError('; '.join(plan['errors']))
    if plan['namespaces'] or plan['host_dnsmasq']:
        raise RuntimeError('Hay namespaces o procesos DHCP residuales de laboratorio.')
    for vlan in (100,200):
        record=cleanup.STATE/'networks'/str(vlan)
        if record.read_text().splitlines()[1]!='no':
            raise RuntimeError(f'VLAN {vlan} no figura con DHCP deshabilitado.')
    print('SIN_DHCP_SERVER3_OK: sin namespaces ni demonios DHCP de laboratorio.')
except (RuntimeError,OSError,IndexError) as e:raise SystemExit(str(e))
