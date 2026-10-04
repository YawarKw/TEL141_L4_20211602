#!/usr/bin/env python3
"""Comprobacion de solo lectura del switch de transito ya provisto por VNRT."""
import json
from pathlib import Path
import subprocess

def cmd(*a):return subprocess.check_output(a,universal_newlines=True).strip()
try:
    assert cmd('hostname','-s').lower()=='ofs', 'El destino no es OFS.'
    addrs=json.loads(cmd('ip','-j','-4','addr','show','dev','ens3'))
    assert any(a.get('local')=='10.0.10.5' for x in addrs for a in x.get('addr_info', [])), 'IP de gestion OFS inesperada.'
    route = cmd('ip','-4','route','get','10.0.10.4').split()
    assert any(route[i]=='dev' and route[i+1]=='ens3' for i in range(len(route)-1)), 'Gestion OFS no usa ens3.'
    physical={p.name for p in Path('/sys/class/net').iterdir() if (p/'device').exists()}-{'ens3'}
    assert len(physical)>=3, 'No se detectaron al menos tres puertos fisicos de datos.'
    bridge_names={cmd('ovs-vsctl','iface-to-br',p) for p in physical}
    assert len(bridge_names)==1, 'Los enlaces de datos no pertenecen a un mismo bridge OVS.'
    bridge=bridge_names.pop()
    assert 'ens3' not in cmd('ovs-vsctl','list-ifaces',bridge).split(), 'El bridge de datos incluye gestion.'
    assert not cmd('ovs-vsctl','get-controller',bridge), 'Hay controlador OpenFlow; revisar sus reglas antes de desplegar.'
    assert 'NORMAL' in cmd('ovs-ofctl','dump-flows',bridge), 'No se encontro conmutacion NORMAL.'
    for p in sorted(physical):
        assert cmd('ovs-vsctl','get','Port',p,'tag')=='[]', f'{p} tiene tag de acceso.'
        mode=cmd('ovs-vsctl','get','Port',p,'vlan_mode').strip('"')
        assert mode in ('[]','trunk'), f'{p} no es trunk.'
        trunks=json.loads(cmd('ovs-vsctl','get','Port',p,'trunks'))
        assert not trunks or {100,200}<=set(trunks), f'{p} no permite ambas VLAN.'
    print('OFS OK:',bridge,'; trunks de datos:',','.join(sorted(physical)))
    print(cmd('ovs-vsctl','show'))
except (AssertionError,subprocess.CalledProcessError,KeyError) as e:
    raise SystemExit('OFS NO APTO: '+str(e))
