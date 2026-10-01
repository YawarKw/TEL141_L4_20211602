#!/usr/bin/env bash
# Defensa especifica A1 frente a reglas antiguas amplias. No vacia INPUT/OUTPUT.
set -euo pipefail
iptables -w -N TEL141_A1
iptables -w -N TEL141_A1_IN
for rule in 'vlan100 vlan200' 'vlan200 vlan100'; do
  read -r incoming outgoing <<< "$rule"
  iptables -w -A TEL141_A1 -i "$incoming" -o "$outgoing" -j DROP
done
for ID in 100 200; do
  if [[ $ID == 100 ]]; then NET=192.168.0.0/24; OTHER=192.168.2.0/24; else NET=192.168.2.0/24; OTHER=192.168.0.0/24; fi
  iptables -w -A TEL141_A1 -i "vlan$ID" -o ens3 -s "$NET" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  iptables -w -A TEL141_A1 -i ens3 -o "vlan$ID" -d "$NET" \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -w -A TEL141_A1 -i "vlan$ID" -j DROP
  iptables -w -A TEL141_A1 -o "vlan$ID" -j DROP
  iptables -w -A TEL141_A1 -s "$NET" -j DROP
  iptables -w -A TEL141_A1 -d "$NET" -j DROP
  # Linux acepta IP locales en otra interfaz: bloquear tambien el gateway opuesto.
  iptables -w -A TEL141_A1_IN -i "vlan$ID" -d "$OTHER" -j DROP
done
iptables -w -A TEL141_A1 -j RETURN
iptables -w -A TEL141_A1_IN -j RETURN
iptables -w -I FORWARD 1 -j TEL141_A1
iptables -w -I INPUT 1 -j TEL141_A1_IN
