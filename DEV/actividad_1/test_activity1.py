#!/usr/bin/env python3
"""Pruebas sin SSH real ni cambios de red: selectores, protecciones y consola.
Las pruebas de orquestacion simulan SSH y validan orden/abortos, no conectividad.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ACTIVITY=Path(__file__).resolve().parents[1]
ROOT=ACTIVITY.parents[1]

def module(name):
    spec=importlib.util.spec_from_file_location(name,ACTIVITY/'helpers'/f'{name}.py')
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj

cleanup=module('cleanup');serial=module('serial_guest')

class Safety(unittest.TestCase):
    def base(self):
        return ('server1',[
            {'ifname':'ens3','addr_info':[{'family':'inet','local':'10.0.10.1'}]},
            {'ifname':'ens4','addr_info':[]}],
            [{'dev':'ens3'}],[{'dev':'ens3'}],{'br-int':['ens4','veth_ovs']},{})

    def test_valid_management(self):
        self.assertEqual(cleanup.guard_management(*self.base()),[])

    def test_management_inside_bridge_refused(self):
        a=list(self.base());a[4]={'br-int':['ens3','ens4']}
        self.assertTrue(cleanup.guard_management(*a))

    def test_controller_route_refused(self):
        a=list(self.base());a[3]=[{'dev':'ens4'}]
        self.assertTrue(cleanup.guard_management(*a))

    def test_default_route_refused(self):
        a=list(self.base());a[2]=[{'dev':'br-int'}]
        self.assertTrue(cleanup.guard_management(*a))

    def test_secondary_management_address_refused(self):
        a=list(self.base());a[1][1]['addr_info']=[{'family':'inet','local':'10.0.10.99'}]
        self.assertTrue(cleanup.guard_management(*a))

    def test_wrong_identity_address_refused(self):
        a=list(self.base());a[0]='server3'
        self.assertTrue(cleanup.guard_management(*a))

    def test_rule_selection_preserves_ssh_and_unrelated_nat(self):
        cases=[('filter','-A INPUT -p tcp --dport 22 -j ACCEPT'),
               ('filter','-A FORWARD -i ens3 -o docker0 -j ACCEPT'),
               ('nat','-A POSTROUTING -o ens3 -j MASQUERADE'),
               ('nat','-A PREROUTING -p tcp --dport 5801 -j DNAT --to-destination 10.0.10.1:22'),
               ('filter','-A FORWARD -s 0.0.0.0/0 -j ACCEPT')]
        import shlex
        for table,r in cases:
            self.assertFalse(cleanup.owned_rule(table,shlex.split(r),{'vlan100','vlan200'}),r)

    def test_rule_selection_removes_both_vlan_directions(self):
        import shlex
        for r in ['-A FORWARD -i vlan100 -o vlan200 -j ACCEPT',
                  '-A FORWARD -i vlan200 -o vlan100 -j ACCEPT',
                  '-A FORWARD -s 192.168.0.0/24 -j ACCEPT',
                  '-A FORWARD -d 192.168.2.12/32 -j ACCEPT']:
            self.assertTrue(cleanup.owned_rule('filter',shlex.split(r),{'vlan100','vlan200'}))

    def test_qemu_identity(self):
        self.assertTrue(cleanup.is_lab_qemu({'exe':'qemu-system-x86_64',
            'argv':['qemu-system-x86_64','-drive','file=/root/vm1_imagen.qcow2,format=qcow2']},set()))
        self.assertFalse(cleanup.is_lab_qemu({'exe':'qemu-system-x86_64',
            'argv':['qemu-system-x86_64','-drive','file=/srv/other.qcow2']},{'tap1'}))
        self.assertFalse(cleanup.is_lab_qemu({'exe':'sshd','argv':['sshd','vm1_imagen.qcow2']},set()))

    def test_no_signal_to_reused_pid(self):
        p={'pid':123,'start':'1','argv':['qemu']}
        with patch.object(cleanup,'process_info',return_value={'start':'2','argv':['sshd']}),patch.object(cleanup.os,'kill') as kill:
            with self.assertRaises(RuntimeError):cleanup.stop(p)
            kill.assert_not_called()

    def test_syntax_all_scripts(self):
        for path in ROOT.rglob('*.sh'):
            with self.subTest(path=path.name):
                result=subprocess.run(['bash','-n',str(path)],capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr)

class SerialConsole(unittest.TestCase):
    def test_cirros_login_and_exit_status(self):
        # Transporte simulado: se prueba el dialogo y el parser sin abrir sockets.
        class Console:
            def __init__(self):self.sent=[];self.pending=[];self.closed=False
            def settimeout(self,value):pass
            def connect(self,path):pass
            def sendall(self,data):
                self.sent.append(data)
                if len(self.sent)==1:self.pending.append(b'cirros login: ')
                elif len(self.sent)==2:self.pending.append(b'Password: ')
                elif len(self.sent)==3:self.pending.append(b'\r\n$ ')
                else:
                    command=data.decode();token=re.search('BEGIN_([a-f0-9]+)',command).group(1)
                    self.pending.append((command+'\r\nBEGIN_'+token+'\r\nSALIDA_REAL\r\nEND_'+token+'=17\r\n$ ').encode())
            def recv(self,size):return self.pending.pop(0)
            def close(self):self.closed=True
        console=Console()
        with patch.object(serial.socket,'socket',return_value=console):
            rc,out=serial.execute('/mock/console.sock','false',5)
        self.assertEqual(console.sent[:3],[b'\n',b'cirros\n',b'gocubsgo\n'])
        self.assertTrue(console.closed);self.assertEqual(rc,17);self.assertEqual(out,'SALIDA_REAL\n')

class Orchestration(unittest.TestCase):
    def simulated(self,fail_action=''):
        td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup)
        root=Path(td.name);project=root/'project';shutil.copytree(ROOT,project,ignore=shutil.ignore_patterns('evidencias','__pycache__'))
        bin_dir=root/'bin';bin_dir.mkdir();calls=root/'calls.jsonl';key=root/'key';key.write_text('MOCK')
        config=project/'DEV/actividad_1/config.sh'
        config.write_text(config.read_text().replace('SSH_KEY="$HOME/.ssh/id_ed25519_tel141_s4"',f'SSH_KEY="{key}"'))
        for cmd,value in [('hostname','server4'),('id','ubuntu')]:
            f=bin_dir/cmd;f.write_text('#!/bin/sh\necho '+value+'\n');f.chmod(0o755)
        ssh=bin_dir/'ssh'
        ssh.write_text('''#!/usr/bin/env python3
import sys,os,json,shlex
args=sys.argv[1:];target=next(x for x in args if x.startswith('ubuntu@'))
role={'1':'server1','2':'server2','3':'server3','5':'ofs'}[target.rsplit('.',1)[1]]
command=args[-1]
if command=='hostname -s; sudo -n true':print(role)
elif command.startswith('mktemp '):print('/tmp/tel141-a1.TEST'+role)
elif command.startswith('tar '):sys.stdin.buffer.read()
elif command.startswith('sudo '):
 a=shlex.split(command);action=a[4]
 with open(os.environ['CALLS'],'a') as f:f.write(json.dumps([role,action])+'\\n')
 print(role,action,'simulado')
 if role+':'+action==os.environ.get('FAIL_ACTION'):sys.exit(1)
''');ssh.chmod(0o755)
        env=dict(os.environ,PATH=str(bin_dir)+os.pathsep+os.environ['PATH'],CALLS=str(calls),FAIL_ACTION=fail_action)
        p=subprocess.run(['bash',str(project/'DEV/actividad_1/actividad1.sh'),'deploy'],env=env,capture_output=True,text=True,timeout=30)
        actions=[json.loads(x) for x in calls.read_text().splitlines()]
        return p,actions

    def test_complete_order(self):
        p,a=self.simulated();self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(a[:4],[[x,'check'] for x in ['server1','server2','server3','ofs']])
        self.assertEqual([x[0] for x in a if x[1]=='clean'],['server1','server2','server3'])
        self.assertEqual([x[0] for x in a if x[1]=='deploy'],['server3','server2','server1'])
        self.assertEqual([x[0] for x in a if x[1]=='verify'],['server1','server2','server3','ofs'])
        self.assertLess(a.index(['server2','assets']),a.index(['server1','clean']))

    def test_no_cleanup_if_any_preflight_fails(self):
        p,a=self.simulated('server3:check');self.assertNotEqual(p.returncode,0)
        self.assertTrue(all(x[1]=='check' for x in a))

    def test_no_cleanup_if_image_preparation_fails(self):
        p,a=self.simulated('server2:assets');self.assertNotEqual(p.returncode,0)
        self.assertFalse(any(x[1] in ('clean','deploy') for x in a))

    def test_no_success_if_validation_fails(self):
        p,a=self.simulated('server1:verify');self.assertNotEqual(p.returncode,0)
        self.assertNotIn('PASS:',p.stdout)

if __name__=='__main__':unittest.main(verbosity=2)
