#!/usr/bin/env bash
set -euo pipefail
(( $# == 2 )) || { echo 'Uso: create_container.sh VLAN IMAGEN' >&2; exit 1; }
ID=$1; IMAGE=$2
[[ $ID == 100 || $ID == 200 ]] || exit 1
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
NAME="a1-cont$ID"; VH="a1c${ID}h"; VN="a1c${ID}n"
if [[ $ID == 100 ]]; then MAC=02:20:21:16:01:00; else MAC=02:20:21:16:02:00; fi
docker run -d --name "$NAME" --hostname "$NAME" --network none \
  --cap-add NET_ADMIN --label tel141.activity=1 "$IMAGE" sleep infinity
PID=$(docker inspect -f '{{.State.Pid}}' "$NAME")
[[ $PID =~ ^[1-9][0-9]*$ ]] || { echo 'Contenedor no esta ejecutandose.' >&2; exit 1; }
ip link add "$VH" type veth peer name "$VN"
ip link set "$VN" netns "$PID"
nsenter -t "$PID" -n ip link set "$VN" name eth0
nsenter -t "$PID" -n ip link set eth0 address "$MAC"
nsenter -t "$PID" -n ip link set eth0 up
ovs-vsctl add-port br-int "$VH" -- set Port "$VH" tag="$ID" vlan_mode=access
ip link set "$VH" up
docker cp "$HERE/dhcp_hook.sh" "$NAME:/tmp/a1-dhcp.sh"
docker exec "$NAME" chmod 755 /tmp/a1-dhcp.sh
docker exec "$NAME" sh -c 'udhcpc -b -i eth0 -p /tmp/udhcpc.pid -t 5 -T 2 -s /tmp/a1-dhcp.sh > /tmp/dhcp.log 2>&1'
echo "Contenedor $NAME conectado a VLAN $ID; cliente DHCP iniciado."
