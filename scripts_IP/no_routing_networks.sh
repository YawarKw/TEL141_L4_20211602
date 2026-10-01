#!/usr/bin/env bash
# Uso: sudo ./no_routing_networks.sh VLAN_1 VLAN_2
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 2 )) || die 'Uso: no_routing_networks.sh VLAN_1 VLAN_2'
vlan "$1"; vlan "$2"; [[ $1 != "$2" ]] || die 'Indique dos VLAN diferentes.'
begin; need iptables
[[ -f $STATE/networks/$1 && -f $STATE/networks/$2 ]] || die 'Faltan registros de las VLAN.'
routing_rules rule_del "$1" "$2"
printf 'Retirados ambos permisos de reenvio entre VLAN %s y VLAN %s.\n' "$1" "$2"
