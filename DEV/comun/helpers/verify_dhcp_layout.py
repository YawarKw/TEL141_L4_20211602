#!/usr/bin/env python3
"""Comprueba los namespaces DHCP del escenario y rechaza servicios residuales."""
import argparse
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import cleanup

def expected_vlans(activity):
    return {1:{100,200},2:set(),3:{100,200},4:{200}}[activity]

def validate_inventory(plan,activity):
    if plan['errors']:raise RuntimeError('; '.join(plan['errors']))
    expected={f'ns-dhcp-{v}' for v in expected_vlans(activity)}
    actual={ns['name'] for ns in plan['namespaces']}
    if actual!=expected:
        raise RuntimeError(f'Namespaces DHCP incorrectos: {sorted(actual)}; esperados {sorted(expected)}.')
    if plan['host_dnsmasq']:
        raise RuntimeError('Hay dnsmasq residual del laboratorio fuera de los namespaces previstos.')

def verify(activity):
    plan=cleanup.inventory('server3');validate_inventory(plan,activity)
    for vlan in (100,200):
        mode='si' if vlan in expected_vlans(activity) else 'no'
        record=cleanup.STATE/'networks'/str(vlan)
        if record.read_text().splitlines()[1]!=mode:
            raise RuntimeError(f'VLAN {vlan}: se esperaba DHCP={mode}.')
        print(f'DHCP_LAYOUT_OK VLAN {vlan}: {mode}')
    if activity==2:print('SIN_DHCP_SERVER3_OK')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('activity',type=int,choices=[1,2,3,4]);a=p.parse_args()
    try:verify(a.activity)
    except (RuntimeError,OSError,IndexError) as e:raise SystemExit(str(e))
