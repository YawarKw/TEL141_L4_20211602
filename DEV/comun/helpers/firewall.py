#!/usr/bin/env python3
"""Politica IPv4 de RF1-3. A3 bloquea todo protocolo encaminado del slice."""
import argparse
import shlex
import subprocess

FORWARD='TEL141_RF'
INPUT='TEL141_RF_IN'

def rules(activity):
    if activity not in (1,2,3):raise ValueError('Actividad invalida')
    forwarding=[['-i','vlan100','-o','vlan200','-j','DROP'],
                ['-i','vlan200','-o','vlan100','-j','DROP']]
    local=[]
    for vlan,net,other in [(100,'192.168.0.0/24','192.168.2.0/24'),
                           (200,'192.168.2.0/24','192.168.0.0/24')]:
        interface=f'vlan{vlan}'
        if activity in (1,2):
            forwarding += [
                ['-i',interface,'-o','ens3','-s',net,'-m','conntrack','--ctstate','NEW,ESTABLISHED,RELATED','-j','ACCEPT'],
                ['-i','ens3','-o',interface,'-d',net,'-m','conntrack','--ctstate','ESTABLISHED,RELATED','-j','ACCEPT']]
        for selector,value in [('-i',interface),('-o',interface),('-s',net),('-d',net)]:
            forwarding.append([selector,value,'-j','DROP'])
        local.append(['-i',interface,'-d',other,'-j','DROP'])
    return {FORWARD:forwarding+[['-j','RETURN']],INPUT:local+[['-j','RETURN']]}

def cmd(*args):return subprocess.check_output(['iptables','-w',*args],text=True).strip()

def normalized(tokens):
    # iptables puede ordenar los estados al imprimir: comparar el conjunto.
    tokens=list(tokens)
    if '--ctstate' in tokens:
        i=tokens.index('--ctstate')+1;tokens[i]=','.join(sorted(tokens[i].split(',')))
    return tokens

def apply(activity):
    for chain,entries in rules(activity).items():
        cmd('-N',chain)
        for entry in entries:cmd('-A',chain,*entry)
    cmd('-I','FORWARD','1','-j',FORWARD)
    cmd('-I','INPUT','1','-j',INPUT)

def verify(activity):
    for base,chain in [('FORWARD',FORWARD),('INPUT',INPUT)]:
        entries=[shlex.split(x) for x in cmd('-S',base).splitlines() if x.startswith('-A ')]
        if not entries or entries[0]!=['-A',base,'-j',chain]:
            raise RuntimeError(f'La proteccion {chain} no es la primera regla de {base}.')
    for chain,expected in rules(activity).items():
        actual=[normalized(shlex.split(x)[2:]) for x in cmd('-S',chain).splitlines() if x.startswith('-A ')]
        if actual!=[normalized(x) for x in expected]:
            raise RuntimeError(f'Las reglas de {chain} no corresponden a la actividad {activity}.')
        print(cmd('-vnL',chain))
    print(f'POLITICA IPv4 OK: actividad {activity}; aislamiento y salida coherentes.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['apply','verify']);p.add_argument('activity',type=int,choices=[1,2,3])
    a=p.parse_args()
    try:(apply if a.mode=='apply' else verify)(a.activity)
    except (RuntimeError,subprocess.CalledProcessError) as e:raise SystemExit(str(e))
