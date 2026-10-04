#!/usr/bin/env python3
"""Inventario y limpieza de recursos TEL141. Sin shell=True, pkill ni flush global.
Los discos antiguos se conservan. Las decisiones usan el estado vivo del nodo.
"""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import time

STATE = Path('/var/lib/tel141-l4')
OVS_BRIDGES = {'br-int', 'ovs1', 'ovs-br1', 'ovs-br2'}
LINUX_BRIDGES = {'br1', 'br-lab1', 'br-lab2'}
NAMESPACES = {'ns-dhcp-server', 'ns1', 'ns2', 'ns-dhcp-vlan100',
              'ns-dhcp-vlan200', 'ns-dhcp-100', 'ns-dhcp-200'}
CONTAINERS = {'container_vlan100', 'container_vlan200'} | {f'a{a}-cont{v}' for a in (1,2,3,4) for v in (100,200)}
VM_NAMES = {'vm1', 'vm2', 'vm100', 'vm200', 'vm_vlan100', 'vm_vlan200',
            'cirros-lab'} | {f'a{a}-vm{v}' for a in (1,2,3,4) for v in (100,200)}
DISKS = {'vm1_imagen.qcow2', 'vm2_imagen.qcow2', 'vm_vlan100_img.qcow2',
         'vm_vlan200_img.qcow2'}
CHAINS = {'TEL141_A1', 'TEL141_A1_IN', 'TEL141_RF', 'TEL141_RF_IN'}
NETWORKS = {ipaddress.ip_network('192.168.0.0/24'), ipaddress.ip_network('192.168.2.0/24')}

def run(*args, ok=True):
    p = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if ok and p.returncode:
        raise RuntimeError(f'{shlex.join(args)}: {p.stderr.strip()}')
    return p

def read_json(*args):
    return json.loads(run(*args).stdout)

def legacy_interface(name):
    return name in {'veth_ovs', 'veth_cont', 'veth_ovs_100', 'veth_ovs_200',
                    'veth_cont_100', 'veth_cont_200', 'tap1', 'tap2', 'tap-lab',
                    'veth-br1', 'veth-br2', 'patch-br1', 'patch-br2',
                    'br1-eth0', 'br1-eth1', 'br1-eth2', 'srv-eth0', 'ns1-eth0', 'ns2-eth0'} or bool(
        re.fullmatch(r'(vlan|gw_vlan|dhcp_v)(100|200)|dh(100|200)[hn]|'
                     r'ovs1-tap[012]|vm_vlan(100|200)_tap|a[1234]c(100|200)[hn]', name))

def process_info(pid):
    try:
        root = Path('/proc') / str(pid)
        args = (root/'cmdline').read_bytes().split(b'\0')
        args = [x.decode(errors='replace') for x in args if x]
        stat = (root/'stat').read_text().rsplit(')', 1)[1].split()
        return {'pid': int(pid), 'start': stat[19], 'state': stat[0],
                'exe': Path(os.readlink(root/'exe')).name, 'argv': args}
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return None

def is_lab_qemu(p, ports):
    if not p['exe'].startswith('qemu-system-'):
        return False
    args = p['argv']
    for i, arg in enumerate(args):
        if arg == '-name' and i+1 < len(args) and args[i+1].split(',')[0] in VM_NAMES:
            return True
        # Cada opcion separada se analiza sin ejecutar texto del proceso.
        for item in arg.split(','):
            if item.startswith('ifname=') and item[7:] in ports:
                return True
            path = item[5:] if item.startswith('file=') else item
            if Path(path).name in DISKS or path.startswith(str(STATE/'vms')+'/'):
                return True
    return False

def owned_rule(table, tokens, interfaces):
    if len(tokens) < 2 or tokens[0] != '-A':
        return False
    if tokens[1] in CHAINS:
        return True
    for flag in ('-j', '-g'):
        if flag in tokens and tokens[tokens.index(flag)+1] in CHAINS:
            return True
    if '--comment' in tokens and tokens[tokens.index('--comment')+1].startswith('TEL141-L4-'):
        return True
    if (table, tokens[1]) not in {('filter','FORWARD'), ('nat','POSTROUTING')}:
        return False
    for i, token in enumerate(tokens[:-1]):
        if token in ('-i','-o') and tokens[i+1] in interfaces:
            return True
        if token in ('-s','-d'):
            try:
                net = ipaddress.ip_network(tokens[i+1], strict=False)
                if any(net.subnet_of(n) for n in NETWORKS):
                    return True
            except (ValueError, TypeError):
                pass
    return False

def guard_management(role, links, routes, route_controller, ovs_members, linux_members):
    errors = []
    expected = '10.0.10.' + role[-1]
    mgmt = next((x for x in links if x['ifname'] == 'ens3'), None)
    data = next((x for x in links if x['ifname'] == 'ens4'), None)
    if not mgmt or expected not in [a['local'] for a in mgmt.get('addr_info', []) if a['family']=='inet']:
        errors.append(f'ens3 no contiene la IP de gestion esperada {expected}.')
    if not data:
        errors.append('No existe ens4.')
    if not route_controller or route_controller[0].get('dev') != 'ens3':
        errors.append('La ruta a server4 no utiliza ens3; no se tocara la red.')
    if not routes or any(r.get('dev') != 'ens3' for r in routes):
        errors.append('Se requiere ruta por defecto IPv4 exclusivamente por ens3.')
    for bridge, members in {**ovs_members, **linux_members}.items():
        if 'ens3' in members:
            errors.append(f'{bridge} incluye ens3 y no puede limpiarse.')
    for item in links:
        if item['ifname'] == 'ens3':
            continue
        if item['ifname'] in OVS_BRIDGES|LINUX_BRIDGES|{'ens4'} or legacy_interface(item['ifname']):
            for a in item.get('addr_info', []):
                if a['family']=='inet' and ipaddress.ip_address(a['local']) in ipaddress.ip_network('10.0.10.0/24'):
                    errors.append(f"{item['ifname']} tiene una IP de gestion; limpieza detenida.")
    return errors

def inventory(role):
    if role not in {'server1','server2','server3'} or run('hostname','-s').stdout.strip().lower() != role:
        raise RuntimeError('Identidad del servidor incorrecta. No se efectuaron cambios.')
    links = read_json('ip','-j','address','show')
    link_details = {x['ifname']:x for x in read_json('ip','-j','-d','link','show')}
    all_br = run('ovs-vsctl','list-br').stdout.split()
    ovs_members = {b:run('ovs-vsctl','list-ifaces',b).stdout.split() for b in all_br if b in OVS_BRIDGES}
    linux_members = {b:[p.name for p in (Path('/sys/class/net')/b/'brif').iterdir()]
                     for b in LINUX_BRIDGES if (Path('/sys/class/net')/b/'bridge').exists()}
    routes = read_json('ip','-j','-4','route','show','default')
    route_controller = read_json('ip','-j','-4','route','get','10.0.10.4')
    errors = guard_management(role, links, routes, route_controller, ovs_members, linux_members)
    ports = set().union(*[set(x) for x in list(ovs_members.values())+list(linux_members.values())]) if ovs_members or linux_members else set()
    candidates = {x['ifname'] for x in links if legacy_interface(x['ifname'])} | ports
    candidates -= {'ens3','ens4','lo'} | OVS_BRIDGES | LINUX_BRIDGES
    for port in candidates:
        if (Path('/sys/class/net')/port/'device').exists():
            errors.append(f'Puerto fisico inesperado {port} en un bridge de laboratorio.')
        for link in links:
            if link['ifname'] != port: continue
            for a in link.get('addr_info', []):
                if a['family']=='inet' and ipaddress.ip_address(a['local']) in ipaddress.ip_network('10.0.10.0/24'):
                    errors.append(f'Puerto candidato {port} contiene una IP de gestion.')
    for b in set(all_br)-OVS_BRIDGES:
        if 'ens4' in run('ovs-vsctl','list-ifaces',b).stdout.split():
            errors.append(f'ens4 esta en bridge desconocido {b}; revisar inventario antes de limpiar.')
    if 'ens4' in link_details and link_details['ens4'].get('master') not in (None,'ovs-system',*LINUX_BRIDGES):
        errors.append('ens4 pertenece a otro dispositivo master no reconocido.')
    all_processes = [process_info(p.name) for p in Path('/proc').iterdir() if p.name.isdigit()]
    all_processes = [p for p in all_processes if p]
    qemus = [p for p in all_processes if is_lab_qemu(p, candidates|{'ens4'})]
    if role=='server2':
        qemu_pids={p['pid'] for p in qemus}
        for line in run('ss','-H','-ltnp','( sport = :5901 or sport = :5902 )').stdout.splitlines():
            pids={int(x) for x in re.findall(r'pid=(\d+)',line)}
            if not pids or not pids <= qemu_pids:
                errors.append('VNC 5901/5902 ocupado por un proceso que no pertenece a las VMs identificadas.')
    # Los TAP de una VM identificada tambien pertenecen a su despliegue residual.
    for proc in qemus:
        for arg in proc['argv']:
            for item in arg.split(','):
                if item.startswith('ifname=') and item[7:] in link_details:
                    tap=item[7:]
                    if tap in {'ens3','ens4','lo'} or (Path('/sys/class/net')/tap/'device').exists():
                        errors.append(f'QEMU usa interfaz protegida {tap}.')
                    else:
                        candidates.add(tap)
    namespaces = [n for n in read_json('ip','-j','netns','list') if n['name'] in NAMESPACES]
    daemons = []
    for ns in namespaces:
        ns['processes'] = []
        for pid in run('ip','netns','pids',ns['name']).stdout.split():
            info = process_info(pid)
            if not info: continue
            ns['processes'].append(info)
            if info['exe'] not in {'dnsmasq','udhcpc','dhclient'}:
                errors.append(f"Proceso no reconocido {info['exe']} PID {pid} en {ns['name']}.")
        for link in read_json('ip','-n',ns['name'],'-j','address','show'):
            if link['ifname'] == 'ens3': errors.append('ens3 se encuentra en un namespace seleccionado.')
            for a in link.get('addr_info', []):
                if a['family']=='inet' and ipaddress.ip_address(a['local']) in ipaddress.ip_network('10.0.10.0/24'):
                    errors.append('Un namespace seleccionado contiene una IP de gestion.')
    ns_pids={p['pid'] for ns in namespaces for p in ns['processes']}
    for proc in all_processes:
        if proc['exe'] != 'dnsmasq' or proc['pid'] in ns_pids: continue
        if os.readlink(f"/proc/{proc['pid']}/ns/net") != os.readlink('/proc/self/ns/net'): continue
        text=' '.join(proc['argv'])
        for i,arg in enumerate(proc['argv']):
            conf = arg.split('=',1)[1] if arg.startswith('--conf-file=') else None
            if arg in {'-C','--conf-file'} and i+1<len(proc['argv']): conf=proc['argv'][i+1]
            if conf and Path(conf).is_file(): text+='\n'+Path(conf).read_text(errors='replace')
        bound = set(re.findall(r'(?:interface=|--interface[ =]|(?:^| )-i )([\w.-]+)', text))
        if bound & (candidates|{'ens4'}):
            if 'ens3' in bound: errors.append('dnsmasq de laboratorio tambien usa ens3.')
            daemons.append(proc)
        elif not bound:
            errors.append(f"dnsmasq PID {proc['pid']} sin interfaz identificable; no se puede descartar DHCP residual.")
    containers=[]
    if shutil.which('docker'):
        result=run('docker','ps','-aq',ok=False)
        if result.returncode: errors.append('Docker instalado pero no accesible; no se pudo inventariar sus contenedores.')
        ids=result.stdout.split()
        for obj in read_json('docker','inspect',*ids) if ids else []:
            name=obj['Name'].lstrip('/'); pid=obj['State']['Pid']; mode=obj['HostConfig']['NetworkMode']
            tied=False
            if pid and mode!='host':
                inside=read_json('nsenter','-t',str(pid),'-n','ip','-j','link')
                host_indices={link_details[p]['ifindex'] for p in candidates if p in link_details}
                tied=any(x.get('link_index') in host_indices for x in inside)
            if name in CONTAINERS or tied or (obj['Config'].get('Labels') or {}).get('tel141.activity') in {'1','2','3','4'}:
                if mode=='host': errors.append(f'Contenedor {name} utiliza la red host; no se eliminara automaticamente.')
                containers.append({'id':obj['Id'],'name':name})
    fw=run('iptables-save').stdout
    rules=[]; table=None; own_chains=[]
    interfaces=candidates|OVS_BRIDGES|LINUX_BRIDGES|{'vlan100','vlan200','gw_vlan100','gw_vlan200'}
    for line in fw.splitlines():
        if line.startswith('*'):table=line[1:]
        if line.startswith(':') and line.split()[0][1:] in CHAINS:
            own_chains.append([table,line.split()[0][1:]])
        if line.startswith('-A '):
            tokens=shlex.split(line)
            if owned_rule(table,tokens,interfaces):rules.append([table,tokens])
    return {'role':role,'management':'ens3','data':'ens4','errors':errors,
            'qemu':qemus,'containers':containers,'namespaces':namespaces,
            'host_dnsmasq':daemons,'ovs_bridges':ovs_members,'linux_bridges':linux_members,
            'virtual_interfaces':sorted(candidates),
            'tap_interfaces':[p for p in candidates if link_details.get(p,{}).get('linkinfo',{}).get('info_kind')=='tun'],
            'rules':rules,'own_chains':own_chains,
            'addresses':links,'routes':routes,'iptables_save':fw,
            'disks':'Conservar discos; archivar registros y deltas gestionados, sin borrar la imagen base.'}

def stop(proc):
    current=process_info(proc['pid'])
    if not current:return
    if current['start']!=proc['start'] or current['argv']!=proc['argv']:
        raise RuntimeError('PID cambio de identidad; limpieza detenida.')
    os.kill(proc['pid'],signal.SIGTERM)
    for _ in range(100):
        current=process_info(proc['pid'])
        if not current or current['state']=='Z':return
        time.sleep(.1)
    raise RuntimeError(f"Proceso {proc['pid']} no termino; no se fuerza su cierre.")

def apply(plan, run_id):
    if plan['errors']:raise RuntimeError('; '.join(plan['errors']))
    backup=Path('/var/lib/tel141-a1-backups')/run_id
    backup.mkdir(parents=True,exist_ok=False)
    (backup/'inventory.json').write_text(json.dumps(plan,indent=2))
    (backup/'iptables.save').write_text(plan['iptables_save'])
    for proc in plan['qemu']+plan['host_dnsmasq']:stop(proc)
    for obj in plan['containers']:run('docker','rm','-f',obj['id'])
    for ns in plan['namespaces']:
        for proc in ns['processes']:stop(proc)
        if run('ip','netns','pids',ns['name']).stdout.strip():
            raise RuntimeError('El namespace aun tiene procesos. No se elimina.')
        run('ip','netns','del',ns['name'])
    for table,tokens in plan['rules']:
        if run('iptables','-w','-t',table,'-C',*tokens[1:],ok=False).returncode==0:
            run('iptables','-w','-t',table,'-D',*tokens[1:])
    for table,chain in plan['own_chains']:
        run('iptables','-w','-t',table,'-F',chain)
        run('iptables','-w','-t',table,'-X',chain)
    for bridge in plan['ovs_bridges']:run('ovs-vsctl','--if-exists','del-br',bridge)
    for bridge in plan['linux_bridges']:
        if (Path('/sys/class/net')/bridge).exists():run('ip','link','del',bridge)
    for iface in plan['virtual_interfaces']:
        if (Path('/sys/class/net')/iface).exists():
            if iface in plan['tap_interfaces']:run('ip','tuntap','del','dev',iface,'mode','tap')
            else:run('ip','link','del',iface)
    # ens4 es exclusivamente de datos; la ruta hacia server4 se verifico por ens3.
    run('ip','-4','addr','flush','dev','ens4')
    run('ip','link','set','ens4','up')
    for dirname in ('networks','internet','vms','activity-id'):
        path=STATE/dirname
        if path.exists():shutil.move(str(path),str(backup/dirname))
    print(f'LIMPIEZA OK en {plan["role"]}. Inventario y discos previos: {backup}')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['plan','apply'])
    parser.add_argument('role',choices=['server1','server2','server3'])
    parser.add_argument('run_id')
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.run_id):raise SystemExit('run_id invalido')
    if os.geteuid()!=0:raise SystemExit('Requiere sudo.')
    try:
        plan=inventory(args.role)
        if args.mode=='plan':
            print(json.dumps(plan,indent=2))
            raise SystemExit(1 if plan['errors'] else 0)
        apply(plan,args.run_id)
    except (RuntimeError,subprocess.TimeoutExpired,OSError,ValueError) as e:
        raise SystemExit(f'ERROR: {e}')
