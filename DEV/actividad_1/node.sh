#!/usr/bin/env bash
# Agente remoto llamado SOLO por actividad1.sh desde server4.
set -euo pipefail
export LC_ALL=C
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
IP_SCRIPTS="$ROOT/scripts_IP"
ACTION=${1:?}; ROLE=${2:?}; RUN_ID=${3:?}
IMAGE=${4:-alpine:3.22}; TEST_IP=${5:-8.8.8.8}; TEST_DNS=${6:-example.com}
STATE=/var/lib/tel141-l4
die() { echo "ERROR $ROLE: $*" >&2; exit 1; }
[[ $(hostname -s) == "$ROLE" ]] || die 'Hostname no coincide con el inventario.'
(( EUID == 0 )) || die 'Se requiere sudo -n.'
[[ $ROLE == server1 || $ROLE == server2 || $ROLE == server3 || $ROLE == ofs ]] || die 'Rol invalido.'
[[ $RUN_ID =~ ^[A-Za-z0-9_-]+$ ]] || die 'run_id invalido.'
exec 8>/var/lock/tel141-a1.lock
flock -n 8 || die 'Otro despliegue esta ejecutandose en este nodo.'
need() { local cmd; for cmd in "$@"; do command -v "$cmd" >/dev/null || die "Falta $cmd; ejecute actividad1.sh deps desde server4."; done; }

guest_command() {
    local addr=$1 gw=$2 peer=$3 other=$4
    # Se exige IP recibida por DHCP, gateway, misma VLAN e Internet ANTES de probar aislamiento.
    printf '%s' "ip -4 addr show dev eth0; ip route; "
    printf '%s' "ip -4 addr show dev eth0 | grep -q '$addr/24' || exit 11; "
    printf '%s' "ip route | grep -q 'default via $gw' || exit 12; "
    printf '%s' "ping -c 3 -W 3 $gw || exit 13; ping -c 3 -W 3 $peer || exit 14; "
    printf '%s' "ping -c 3 -W 3 $TEST_IP || exit 15; nslookup $TEST_DNS || exit 16; "
    printf '%s' "if ping -c 2 -W 2 $other; then echo FALLO_AISLAMIENTO; exit 17; fi; echo AISLAMIENTO_OK"
}

case "$ACTION" in
  deps)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y python3 iproute2 iptables util-linux openvswitch-switch curl
    systemctl enable --now openvswitch-switch
    case "$ROLE" in
      server1) apt-get install -y docker.io; systemctl enable --now docker ;;
      server2) apt-get install -y qemu-system-x86 qemu-utils ;;
      server3) apt-get install -y dnsmasq-base ;;
    esac
    ;;
  check)
    need python3 ip ovs-vsctl ovs-ofctl iptables iptables-save nsenter flock
    ovs-vsctl show >/dev/null
    if [[ $ROLE == ofs ]]; then python3 "$HERE/helpers/check_ofs.py"; exit; fi
    case "$ROLE" in
      server1) need docker; docker info >/dev/null ;;
      server2)
        need qemu-system-x86_64 qemu-img curl ss sha256sum
        [[ -r /dev/kvm && -w /dev/kvm ]] || die 'KVM no disponible.' ;;
      server3) need dnsmasq sysctl ;;
    esac
    python3 "$HERE/helpers/cleanup.py" plan "$ROLE" "$RUN_ID"
    ;;
  assets)
    case "$ROLE" in
      server1)
        docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
        docker image inspect --format '{{json .RepoDigests}}' "$IMAGE"
        docker run --rm --network none "$IMAGE" sh -c 'command -v udhcpc; command -v ip; command -v ifconfig; command -v nslookup' ;;
      server2)
        mkdir -p "$STATE/images"
        BASE="$STATE/images/cirros-0.5.1-x86_64-disk.img"
        if [[ ! -s $BASE ]]; then
          IMPORTED=0
          for SRC in /home/ubuntu/cirros-0.5.1-x86_64-disk.img /root/cirros-0.5.1-x86_64-disk.img; do
            if [[ -s $SRC ]] && qemu-img info -f qcow2 "$SRC" >/dev/null 2>&1; then
              cp -- "$SRC" "$BASE.part"; IMPORTED=1; break
            fi
          done
          if (( ! IMPORTED )); then
            curl --fail --location --connect-timeout 10 --max-time 180 --retry 2 \
              -o "$BASE.part" https://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img
          fi
          qemu-img info -f qcow2 "$BASE.part" >/dev/null
          mv -- "$BASE.part" "$BASE"; chmod 444 "$BASE"
        fi
        qemu-img info -f qcow2 "$BASE" ;;
    esac
    ;;
  clean)
    [[ $ROLE != ofs ]] || die 'No se limpia OFS.'
    mkdir -p "$STATE"
    flock -x "$STATE/lock" python3 "$HERE/helpers/cleanup.py" apply "$ROLE" "$RUN_ID"
    ;;
  deploy)
    case "$ROLE" in
      server3)
        bash "$IP_SCRIPTS/init_master.sh" ens4
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then PREFIX=192.168.0; M=01; else PREFIX=192.168.2; M=02; fi
          printf 'dhcp-host=02:20:21:16:%s:00,%s.11\ndhcp-host=02:20:21:16:%s:01,%s.12\n' \
            "$M" "$PREFIX" "$M" "$PREFIX" > "$HERE/reservas-$ID.conf"
          TEL141_DHCP_HOSTS_FILE="$HERE/reservas-$ID.conf" bash "$IP_SCRIPTS/create_network_vlan.sh" \
            "$ID" "$PREFIX.0/24" si "$PREFIX.11,$PREFIX.15"
          EXT_IF=ens3 bash "$IP_SCRIPTS/internet_to_network.sh" "$ID" "$PREFIX.0/24"
        done
        bash "$HERE/helpers/firewall_a1.sh"
        ;;
      server2)
        bash "$IP_SCRIPTS/init_worker.sh" ens4
        TEL141_MAC=02:20:21:16:01:01 TEL141_SERIAL=1 bash "$IP_SCRIPTS/create_vm.sh" a1-vm100 br-int 100 5901
        TEL141_MAC=02:20:21:16:02:01 TEL141_SERIAL=1 bash "$IP_SCRIPTS/create_vm.sh" a1-vm200 br-int 200 5902
        ;;
      server1)
        bash "$IP_SCRIPTS/init_worker.sh" ens4
        bash "$HERE/helpers/create_container.sh" 100 "$IMAGE"
        bash "$HERE/helpers/create_container.sh" 200 "$IMAGE"
        ;;
      *) die 'OFS se valida, no se modifica.' ;;
    esac
    ;;
  ready)
    case "$ROLE" in
      server1)
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then ADDR=192.168.0.11; else ADDR=192.168.2.11; fi
          READY=0
          for ((i=0;i<45;i++)); do
            if docker exec "a1-cont$ID" ip -4 addr show dev eth0 | grep -Fq "$ADDR/24"; then READY=1; break; fi
            sleep 2
          done
          docker exec "a1-cont$ID" cat /tmp/dhcp.log
          (( READY )) || die "Contenedor VLAN $ID no obtuvo la reserva DHCP."
        done ;;
      server2)
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then ADDR=192.168.0.12; else ADDR=192.168.2.12; fi
          python3 "$HERE/helpers/serial_guest.py" "$STATE/vms/a1-vm$ID/serial.sock" \
            "i=0; while [ \"\$i\" -lt 45 ]; do ip -4 addr show dev eth0 | grep -q '$ADDR/24' && exit 0; i=\$((i+1)); sleep 2; done; ip addr; exit 1" \
            --timeout 300
        done ;;
    esac
    ;;
  verify)
    ovs-vsctl show
    case "$ROLE" in
      server1)
        docker ps --filter label=tel141.activity=1
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then NET=192.168.0; OTHER=192.168.2.12; else NET=192.168.2; OTHER=192.168.0.12; fi
          echo "VERIFICANDO CONTENEDOR VLAN $ID"
          docker exec "a1-cont$ID" sh -c "$(guest_command "$NET.11" "$NET.1" "$NET.12" "$OTHER")"
        done ;;
      server2)
        ss -lntp '( sport = :5901 or sport = :5902 )'
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then NET=192.168.0; OTHER=192.168.2.11; else NET=192.168.2; OTHER=192.168.0.11; fi
          echo "VERIFICANDO VM VLAN $ID"
          python3 "$HERE/helpers/serial_guest.py" "$STATE/vms/a1-vm$ID/serial.sock" \
            "$(guest_command "$NET.12" "$NET.1" "$NET.11" "$OTHER")" --timeout 90
        done ;;
      server3)
        [[ $(sysctl -n net.ipv4.ip_forward) == 1 ]] || die 'Forwarding deshabilitado.'
        [[ $(iptables -S FORWARD | head -n 1) == '-P FORWARD DROP' ]] || die 'Politica incorrecta.'
        iptables -C FORWARD -j TEL141_A1
        iptables -C INPUT -j TEL141_A1_IN
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then NET=192.168.0; M=01; else NET=192.168.2; M=02; fi
          ip -4 addr show "vlan$ID"
          ip netns exec "ns-dhcp-$ID" ip -4 addr
          LISTEN=$(ip netns exec "ns-dhcp-$ID" ss -H -lun 'sport = :67')
          [[ -n $LISTEN ]] || die "DHCP VLAN $ID no escucha."
          echo "$LISTEN"
          cat "$STATE/networks/dnsmasq-$ID.leases"
          for LAST in 00 01; do
            [[ $LAST == 00 ]] && END=11 || END=12
            awk -v mac="02:20:21:16:$M:$LAST" -v addr="$NET.$END" \
              '$2==mac && $3==addr {ok=1} END {exit !ok}' "$STATE/networks/dnsmasq-$ID.leases" \
              || die "Falta concesion DHCP $NET.$END."
          done
          iptables -t nat -C POSTROUTING -s "$NET.0/24" -o ens3 \
            -m comment --comment "TEL141-L4-internet-$ID" -j MASQUERADE
        done
        iptables -vnL TEL141_A1
        iptables -vnL TEL141_A1_IN
        iptables -t nat -vnL POSTROUTING
        ;;
      ofs) python3 "$HERE/helpers/check_ofs.py" ;;
    esac
    echo "VERIFICACION OK $ROLE"
    ;;
  *) die 'Accion no admitida.' ;;
esac
