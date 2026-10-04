#!/usr/bin/env python3
"""Ejecuta verificaciones en la consola serie de CirrOS; no instala agentes.
Credenciales predeterminadas de la imagen de laboratorio: cirros / gocubsgo.
Solo se imprime la salida de la orden, no el dialogo de autenticacion.
"""
import argparse
import os
import base64
import re
import shlex
import socket
import sys
import time
import uuid

def execute(path, command, timeout=240):
    sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    sock.settimeout(1)
    sock.connect(path)
    deadline=time.monotonic()+int(os.environ.get('TEL141_SERIAL_TIMEOUT', timeout))
    buf=''; last=time.monotonic(); auth=0
    sock.sendall(b'\n')
    try:
        while time.monotonic()<deadline:
            try:data=sock.recv(65536)
            except socket.timeout:data=b''
            if data:buf+=data.decode(errors='replace').replace('\r','')
            if re.search(r'(?m)^[^\n]*login:\s*$',buf):
                if auth>=3:raise RuntimeError('No se pudo autenticar en CirrOS.')
                sock.sendall(b'cirros\n');buf='';auth+=1
            elif re.search(r'(?im)^password:\s*$',buf):
                sock.sendall(b'gocubsgo\n');buf=''
            elif re.search(r'(?m)^[ \t]*\$[ \t]*$',buf):
                break
            if time.monotonic()-last>8:
                sock.sendall(b'\n');last=time.monotonic()
        else:raise RuntimeError('Consola no reconocida. Ultima respuesta: ' + repr(buf[-3000:]))
        token=uuid.uuid4().hex
        begin='BEGIN_'+token; end='END_'+token
        encoded=base64.b64encode(command.encode()).decode()
        remote='/tmp/tel141-'+token+'.b64'
        tag='PAYLOAD_'+token
        lines=[f"cat > {remote} <<'{tag}'"]
        lines += [encoded[i:i+120] for i in range(0,len(encoded),120)]
        lines += [tag, f'echo; echo {begin}; base64 -d {remote} | sh; rc=$?; rm -f {remote}; echo; echo "{end}=$rc"']
        for line in lines:
            sock.sendall((line+'\n').encode())
            time.sleep(0.03)
        buf=''
        while time.monotonic()<deadline:
            try:data=sock.recv(65536)
            except socket.timeout:continue
            if not data:raise RuntimeError('QEMU cerro la consola.')
            buf+=data.decode(errors='replace').replace('\r','')
            match=re.search(r'(?m)^'+end+r'=(\d+)\s*$',buf)
            start=re.search(r'(?m)^'+begin+r'\s*\n',buf)
            if match and start:
                return int(match.group(1)),buf[start.end():match.start()]
        raise RuntimeError('La orden del invitado no termino dentro del plazo. Ultima salida: ' + repr(buf[-6000:]))
    finally:sock.close()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('socket');p.add_argument('command');p.add_argument('--timeout',type=int,default=240)
    a=p.parse_args()
    try:
        rc,out=execute(a.socket,a.command,a.timeout)
        print(out,end='');sys.exit(rc)
    except (RuntimeError,OSError) as e:sys.exit(str(e))
