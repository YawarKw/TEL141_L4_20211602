#!/usr/bin/env python3
"""Ejecuta verificaciones en la consola serie de CirrOS; no instala agentes.
Credenciales predeterminadas de la imagen de laboratorio: cirros / gocubsgo.
Solo se imprime la salida de la orden, no el dialogo de autenticacion.
"""
import argparse
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
    deadline=time.monotonic()+timeout
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
            elif re.search(r'(?m)^[^\n]*[#$]\s*$',buf):
                break
            if time.monotonic()-last>8:
                sock.sendall(b'\n');last=time.monotonic()
        else:raise RuntimeError('CirrOS no presento consola utilizable dentro del plazo.')
        token=uuid.uuid4().hex
        begin='BEGIN_'+token; end='END_'+token
        line=f"printf '\\n{begin}\\n'; sh -c {shlex.quote(command)}; rc=$?; printf '\\n{end}=%s\\n' \"$rc\"\n"
        sock.sendall(line.encode());buf=''
        while time.monotonic()<deadline:
            try:data=sock.recv(65536)
            except socket.timeout:continue
            if not data:raise RuntimeError('QEMU cerro la consola.')
            buf+=data.decode(errors='replace').replace('\r','')
            match=re.search(r'(?m)^'+end+r'=(\d+)\s*$',buf)
            start=re.search(r'(?m)^'+begin+r'\s*\n',buf)
            if match and start:
                return int(match.group(1)),buf[start.end():match.start()]
        raise RuntimeError('La orden del invitado no termino dentro del plazo.')
    finally:sock.close()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('socket');p.add_argument('command');p.add_argument('--timeout',type=int,default=240)
    a=p.parse_args()
    try:
        rc,out=execute(a.socket,a.command,a.timeout)
        print(out,end='');sys.exit(rc)
    except (RuntimeError,OSError) as e:sys.exit(str(e))
