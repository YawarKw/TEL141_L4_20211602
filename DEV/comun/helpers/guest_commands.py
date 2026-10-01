#!/usr/bin/env python3
"""Ordenes de verificacion para los invitados; sus errores no se ocultan."""
import argparse
import ipaddress
import re
import shlex

def command(activity,vlan,kind,test_ip='8.8.8.8',dns_name='example.com'):
    if activity not in (1,2,3) or vlan not in (100,200) or kind not in ('container','vm'):
        raise ValueError('Perfil invalido')
    ipaddress.IPv4Address(test_ip)
    if not re.fullmatch(r'[A-Za-z0-9.-]+',dns_name):raise ValueError('Nombre DNS invalido')
    prefix='192.168.0' if vlan==100 else '192.168.2'
    opposite='192.168.2' if vlan==100 else '192.168.0'
    end,peer=('11','12') if kind=='container' else ('12','11')
    addr=f'{prefix}.{end}';gw=prefix+'.1'
    parts=['ip -4 addr show dev eth0','ip route',
           f"ip -4 addr show dev eth0 | grep -Fq '{addr}/24' || exit 11",
           f"ip route | grep -Fq 'default via {gw} ' || exit 12"]
    if activity==2:
        parts+=['command -v pidof >/dev/null || exit 18',
                'if pidof udhcpc dhclient dhcpcd >/dev/null 2>&1; then echo FALLO_CLIENTE_DHCP; exit 18; fi']
    parts += [f'ping -c 3 -W 3 {gw} || exit 13',f'ping -c 3 -W 3 {prefix}.{peer} || exit 14']
    if activity in (1,2):
        parts += [f'ping -c 3 -W 3 {test_ip} || exit 15',f'nslookup {shlex.quote(dns_name)} || exit 16','echo INTERNET_OK']
    else:
        # Capturar rc evita aceptar errores de sintaxis/permisos como bloqueo.
        parts += [f'ping -c 2 -W 2 {test_ip}; rc=$?',
                  'if [ "$rc" -eq 0 ]; then echo FALLO_INTERNET_PERMITIDO; exit 19; fi',
                  '[ "$rc" -eq 1 ] || exit 20','echo INTERNET_BLOQUEADO_OK']
    parts += [f'ping -c 2 -W 2 {opposite}.{peer}; rc=$?',
              'if [ "$rc" -eq 0 ]; then echo FALLO_AISLAMIENTO; exit 17; fi',
              '[ "$rc" -eq 1 ] || exit 20','echo AISLAMIENTO_OK']
    return '; '.join(parts)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('activity',type=int);p.add_argument('vlan',type=int)
    p.add_argument('kind');p.add_argument('test_ip');p.add_argument('dns_name');a=p.parse_args()
    print(command(a.activity,a.vlan,a.kind,a.test_ip,a.dns_name))
