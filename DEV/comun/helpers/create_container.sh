#!/usr/bin/env bash
set -euo pipefail
(( $# == 3 )) || { echo 'Uso: create_container.sh VLAN IMAGEN ACTIVIDAD' >&2; exit 1; }
ID=$1; IMAGE=$2; ACTIVITY_ID=$3
[[ $ACTIVITY_ID =~ ^[123]$ ]] || exit 1
[[ $ID == 100 || $ID == 200 ]] || exit 1
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
NAME="a${ACTIVITY_ID}-cont$ID"; VH="a${ACTIVITY_ID}c${ID}h"; VN="a${ACTIVITY_ID}c${ID}n"
if [[ $ID == 100 ]]; then MAC=02:20:21:16:01:00; else MAC=02:20:21:16:02:00; fi
docker run -d --name "$NAME" --hostname "$NAME" --network none \
  --cap-add NET_ADMIN --label "tel141.activity=$ACTIVITY_ID" "$IMAGE" sleep infinity
PID=$(docker inspect -f '{{.State.Pid}}' "$NAME")
[[ $PID =~ ^[1-9][0-9]*$ ]] || { echo 'Contenedor no esta ejecutandose.' >&2; exit 1; }
ip link add "$VH" type veth peer name "$VN"
ip link set "$VN" netns "$PID"
nsenter -t "$PID" -n ip link set "$VN" name eth0
nsenter -t "$PID" -n ip link set eth0 address "$MAC"
nsenter -t "$PID" -n ip link set eth0 up
ovs-vsctl add-port br-int "$VH" -- set Port "$VH" tag="$ID" vlan_mode=access
ip link set "$VH" up
if [[ $ACTIVITY_ID == 2 ]]; then
  if [[ $ID == 100 ]]; then PREFIX=192.168.0; else PREFIX=192.168.2; fi
  docker exec "$NAME" ip addr add "$PREFIX.11/24" dev eth0
  docker exec "$NAME" ip route replace default via "$PREFIX.1" dev eth0
  docker exec "$NAME" sh -c 'printf "nameserver 8.8.8.8\n" > /etc/resolv.conf'
  echo "Contenedor $NAME con IP estatica $PREFIX.11/24; no se inicia DHCP."
else
  docker cp "$HERE/dhcp_hook.sh" "$NAME:/tmp/rf-dhcp.sh"
  docker exec "$NAME" chmod 755 /tmp/rf-dhcp.sh
  docker exec "$NAME" sh -c 'udhcpc -b -i eth0 -p /tmp/udhcpc.pid -t 5 -T 2 -s /tmp/rf-dhcp.sh > /tmp/dhcp.log 2>&1'
  echo "Contenedor $NAME conectado a VLAN $ID; cliente DHCP iniciado."
fi
