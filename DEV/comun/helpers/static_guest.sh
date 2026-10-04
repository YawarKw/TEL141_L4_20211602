#!/bin/sh
# Se envia por consola serie y se ejecuta DENTRO de una VM CirrOS dedicada.
# Nunca ejecutar en server1-4: cambia eth0 y /etc/network/interfaces del invitado.
set -eu
ADDR=${1:?}; GW=${2:?}
case "$ADDR:$GW" in
  192.168.0.12:192.168.0.1|192.168.2.12:192.168.2.1) ;;
  *) echo 'Direccion no prevista para la VM estatica de A2/A4'; exit 1 ;;
esac
[ "$(id -u)" -eq 0 ]
command -v pidof >/dev/null
ifdown eth0 2>/dev/null || true
# Solo esta VM recien creada: cerrar sus clientes DHCP, no procesos del host.
for p in $(pidof udhcpc dhclient dhcpcd 2>/dev/null || true); do kill -TERM "$p"; done
i=0
while pidof udhcpc dhclient dhcpcd >/dev/null 2>&1; do
    i=$((i+1)); [ "$i" -lt 10 ] || { echo 'Cliente DHCP no termino'; exit 1; }
    sleep 1
done
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
    address $ADDR
    netmask 255.255.255.0
    gateway $GW
EOF
ip -4 addr flush dev eth0
ip addr add "$ADDR/24" dev eth0
ip link set eth0 up
ip route replace default via "$GW" dev eth0
printf 'nameserver 8.8.8.8\n' > /etc/resolv.conf
printf 'ESTATICA_OK %s; DHCP detenido dentro de la VM\n' "$ADDR"
cat /etc/network/interfaces
ip -4 addr show dev eth0
ip route
