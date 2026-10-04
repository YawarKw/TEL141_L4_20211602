#!/usr/bin/env bash
# Direcciones de gestion confirmadas en la grafica 1 del reporte final.
SSH_USER=ubuntu
SSH_PORT=22
SSH_KEY="$HOME/.ssh/id_ed25519_tel141_s4"
declare -A HOSTS=(
  [server1]=10.0.10.1
  [server2]=10.0.10.2
  [server3]=10.0.10.3
  [ofs]=10.0.10.5
)
# Se comprueba hostname antes de modificar cualquier nodo.
DOCKER_IMAGE=alpine:3.22
INTERNET_TEST_IP=8.8.8.8
DNS_TEST_NAME=example.com
