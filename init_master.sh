#!/usr/bin/env bash
# Uso: sudo ./init_master.sh INTERFAZ_DATOS [OTRA_INTERFAZ...]
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# >= 1 )) || die 'Uso: init_master.sh INTERFAZ [INTERFAZ...]'
begin; need sysctl iptables
init_bridge "$@"
sysctl -w net.ipv4.ip_forward=1
iptables -w -t filter -P FORWARD DROP
printf 'Master listo: br-int, forwarding IPv4=1 y politica FORWARD=DROP.\n'
