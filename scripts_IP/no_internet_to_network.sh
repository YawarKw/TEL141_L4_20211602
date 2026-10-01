#!/usr/bin/env bash
# Uso: sudo ./no_internet_to_network.sh VLAN RED_CIDR
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 2 )) || die 'Uso: no_internet_to_network.sh VLAN RED/CIDR'
vlan "$1"; cidr "$2"; ID=$1
begin; need iptables
[[ -f $STATE/networks/$ID ]] || die 'VLAN sin registro.'
[[ $(get_network "$ID") == "$NETWORK" ]] || die 'CIDR no coincide con la VLAN.'
if [[ ! -f $STATE/internet/$ID ]]; then printf 'No hay permiso de Internet registrado.\n'; exit 0; fi
read -r EXT < "$STATE/internet/$ID"
internet_rules rule_del "$ID" "$NETWORK" "$EXT"
rm -f "$STATE/internet/$ID"
printf 'Retiradas las reglas propias de NAT y FORWARD de VLAN %s.\n' "$ID"
