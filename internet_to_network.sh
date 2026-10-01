#!/usr/bin/env bash
# Uso: sudo ./internet_to_network.sh VLAN RED_CIDR
# Salida alternativa: sudo env EXT_IF=ens3 ./internet_to_network.sh ...
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 2 )) || die 'Uso: internet_to_network.sh VLAN RED/CIDR'
vlan "$1"; cidr "$2"; ID=$1
begin; need iptables
network_exists "$ID"
[[ $(get_network "$ID") == "$NETWORK" ]] || die 'CIDR no coincide con la VLAN.'
if [[ -n ${EXT_IF:-} ]]; then
    EXT=$EXT_IF
else
    mapfile -t EXTS < <(ip -o -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u)
    (( ${#EXTS[@]} == 1 )) || die 'No hay una unica salida; indique EXT_IF.'
    EXT=${EXTS[0]}
fi
if_ok "$EXT"; ip link show "$EXT" >/dev/null
[[ $EXT != vlan* && $EXT != "$BR" && $EXT != lo ]] || die 'La salida debe ser una interfaz externa.'
RECORD="$STATE/internet/$ID"
if [[ -f $RECORD ]]; then
    read -r OLD < "$RECORD"
    [[ $OLD == "$EXT" ]] || die 'Retire el permiso anterior antes de cambiar EXT_IF.'
fi
printf '%s\n' "$EXT" > "$RECORD"
internet_rules rule_add "$ID" "$NETWORK" "$EXT"
printf 'VLAN %s con NAT y FORWARD por %s.\n' "$ID" "$EXT"
