#!/usr/bin/env bash
# Uso: sudo ./routing_networks.sh VLAN_1 VLAN_2
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 2 )) || die 'Uso: routing_networks.sh VLAN_1 VLAN_2'
vlan "$1"; vlan "$2"; [[ $1 != "$2" ]] || die 'Indique dos VLAN diferentes.'
begin; need iptables
network_exists "$1"; network_exists "$2"
routing_rules rule_add "$1" "$2"
printf 'Reenvio permitido entre VLAN %s y VLAN %s, en ambos sentidos.\n' "$1" "$2"
