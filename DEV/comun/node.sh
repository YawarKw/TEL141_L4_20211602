#!/usr/bin/env bash
# Agente remoto llamado SOLO por actividadN.sh desde server4.
set -euo pipefail
export LC_ALL=C
export PYTHONDONTWRITEBYTECODE=1
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
IP_SCRIPTS="$ROOT/scripts_IP"
ACTION=${1:?}; ROLE=${2:?}; RUN_ID=${3:?}
IMAGE=${4:-alpine:3.22}; TEST_IP=${5:-8.8.8.8}; TEST_DNS=${6:-example.com}
ACTIVITY_ID=${7:?}; [[ $ACTIVITY_ID =~ ^[1234]$ ]] || exit 2
STATE=/var/lib/tel141-l4
source "$HERE/helpers/profile.sh"
die() { echo "ERROR $ROLE: $*" >&2; exit 1; }
[[ $(hostname -s) == "$ROLE" ]] || die 'Hostname no coincide con el inventario.'
(( EUID == 0 )) || die 'Se requiere sudo -n.'
[[ $ROLE == server1 || $ROLE == server2 || $ROLE == server3 || $ROLE == ofs ]] || die 'Rol invalido.'
[[ $RUN_ID =~ ^[A-Za-z0-9_-]+$ ]] || die 'run_id invalido.'
exec 8>/var/lock/tel141-a1.lock
flock -n 8 || die 'Otro despliegue esta ejecutandose en este nodo.'
need() { local cmd; for cmd in "$@"; do command -v "$cmd" >/dev/null || die "Falta $cmd; ejecute actividadN.sh deps desde server4."; done; }

guest_command() {
    python3 "$HERE/helpers/guest_commands.py" "$ACTIVITY_ID" "$1" "$2" "$TEST_IP" "$TEST_DNS"
}
vm_console() {
    local id=$1 command=$2 timeout=${3:-150}
    python3 "$HERE/helpers/serial_guest.py" "$STATE/vms/a${ACTIVITY_ID}-vm$id/serial.sock" "$command" --timeout "$timeout"
}

case "$ACTION" in
  deps)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y python3 iproute2 iptables util-linux openvswitch-switch curl iputils-ping
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
        need qemu-system-x86_64 qemu-img curl ss sha256sum base64
        [[ -r /dev/kvm && -w /dev/kvm ]] || die 'KVM no disponible.' ;;
      server3) need dnsmasq sysctl ping ;;
    esac
    python3 "$HERE/helpers/cleanup.py" plan "$ROLE" "$RUN_ID"
    ;;
  assets)
    case "$ROLE" in
      server1)
        docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
        docker image inspect --format '{{json .RepoDigests}}' "$IMAGE"
        docker run --rm --network none "$IMAGE" sh -c 'set -e; for c in udhcpc ip ifconfig nslookup ping pidof; do command -v "$c"; done' ;;
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
          if is_static_vlan "$ID"; then
            bash "$IP_SCRIPTS/create_network_vlan.sh" "$ID" "$PREFIX.0/24" no
          else
            printf 'dhcp-host=02:20:21:16:%s:00,%s.11\ndhcp-host=02:20:21:16:%s:01,%s.12\n' \
              "$M" "$PREFIX" "$M" "$PREFIX" > "$HERE/reservas-$ID.conf"
            TEL141_DHCP_HOSTS_FILE="$HERE/reservas-$ID.conf" bash "$IP_SCRIPTS/create_network_vlan.sh" \
              "$ID" "$PREFIX.0/24" si "$PREFIX.11,$PREFIX.15"
          fi
          if ! internet_enabled; then
            bash "$IP_SCRIPTS/no_internet_to_network.sh" "$ID" "$PREFIX.0/24"
          else
            EXT_IF=ens3 bash "$IP_SCRIPTS/internet_to_network.sh" "$ID" "$PREFIX.0/24"
          fi
        done
        if [[ $ACTIVITY_ID == 4 ]]; then
          bash "$IP_SCRIPTS/routing_networks.sh" 100 200
        fi
        python3 "$HERE/helpers/firewall.py" apply "$ACTIVITY_ID"
        ;;
      server2)
        bash "$IP_SCRIPTS/init_worker.sh" ens4
        TEL141_MAC=02:20:21:16:01:01 TEL141_SERIAL=1 bash "$IP_SCRIPTS/create_vm.sh" "a${ACTIVITY_ID}-vm100" br-int 100 5901
        TEL141_MAC=02:20:21:16:02:01 TEL141_SERIAL=1 bash "$IP_SCRIPTS/create_vm.sh" "a${ACTIVITY_ID}-vm200" br-int 200 5902
        ;;
      server1)
        bash "$IP_SCRIPTS/init_worker.sh" ens4
        bash "$HERE/helpers/create_container.sh" 100 "$IMAGE" "$ACTIVITY_ID"
        bash "$HERE/helpers/create_container.sh" 200 "$IMAGE" "$ACTIVITY_ID"
        ;;
      *) die 'OFS se valida, no se modifica.' ;;
    esac
    printf '%s\n' "$ACTIVITY_ID" > "$STATE/activity-id"
    ;;
  ready)
    case "$ROLE" in
      server1)
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then ADDR=192.168.0.11; else ADDR=192.168.2.11; fi
          READY=0
          for ((i=0;i<45;i++)); do
            if docker exec "a${ACTIVITY_ID}-cont$ID" ip -4 addr show dev eth0 | grep -Fq "$ADDR/24"; then READY=1; break; fi
            sleep 2
          done
          if ! is_static_vlan "$ID"; then docker exec "a${ACTIVITY_ID}-cont$ID" cat /tmp/dhcp.log; fi
          (( READY )) || die "Contenedor VLAN $ID sin la direccion esperada."
        done ;;
      server2)
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then PREFIX=192.168.0; else PREFIX=192.168.2; fi
          if is_static_vlan "$ID"; then
            # Enviar un script corto codificado; el invitado lo ejecuta con sudo.
            PAYLOAD=$(base64 -w 0 "$HERE/helpers/static_guest.sh")
            vm_console "$ID" "command -v base64 >/dev/null || exit 23; printf '%s' '$PAYLOAD' | base64 -d | sudo -n sh -s -- $PREFIX.12 $PREFIX.1" 420
          else
            vm_console "$ID" \
              "i=0; while [ \"\$i\" -lt 45 ]; do ip -4 addr show dev eth0 | grep -Fq '$PREFIX.12/24' && exit 0; i=\$((i+1)); sleep 2; done; ip addr; exit 1" 300
          fi
        done ;;
    esac
    ;;
  verify)
    ovs-vsctl show
    if [[ $ROLE != ofs ]]; then
      [[ -f $STATE/activity-id && $(cat "$STATE/activity-id") == "$ACTIVITY_ID" ]] || die 'El nodo no tiene desplegada esta actividad con esta version.'
    fi
    case "$ROLE" in
      server1)
        docker ps --filter "label=tel141.activity=$ACTIVITY_ID"
        for ID in 100 200; do
          echo "VERIFICANDO CONTENEDOR VLAN $ID, actividad $ACTIVITY_ID"
          docker exec "a${ACTIVITY_ID}-cont$ID" sh -c "$(guest_command "$ID" container)"
          if is_static_vlan "$ID"; then
            # Prueba temporal: /bin/true evita modificar la IP estatica.
            docker exec "a${ACTIVITY_ID}-cont$ID" sh -c '
              udhcpc -f -n -q -t 2 -T 2 -i eth0 -s /bin/true; rc=$?
              if [ "$rc" -eq 0 ]; then echo FALLO_DHCP_RESIDUAL; exit 21; fi
              [ "$rc" -eq 1 ] || exit 22
              echo SIN_OFERTAS_DHCP_OK'
          fi
        done ;;
      server2)
        ss -lntp '( sport = :5901 or sport = :5902 )'
        for ID in 100 200; do
          echo "VERIFICANDO VM VLAN $ID, actividad $ACTIVITY_ID"
          vm_console "$ID" "$(guest_command "$ID" vm)"
        done ;;
      server3)
        [[ $(sysctl -n net.ipv4.ip_forward) == 1 ]] || die 'Forwarding deshabilitado.'
        FORWARD_RULES=$(iptables -S FORWARD)
        [[ ${FORWARD_RULES%%$'\n'*} == '-P FORWARD DROP' ]] || die 'Politica incorrecta.'
        python3 "$HERE/helpers/firewall.py" verify "$ACTIVITY_ID"
        # Control positivo: el host de gestion sigue teniendo salida real.
        ping -I ens3 -c 3 -W 3 "$TEST_IP" || die 'server3 tampoco alcanza Internet; no se puede validar el escenario.'
        echo INTERNET_HOST_OK
        python3 "$HERE/helpers/verify_dhcp_layout.py" "$ACTIVITY_ID"
        if [[ $ACTIVITY_ID == 4 ]]; then
          ip -4 route
          iptables -C FORWARD -i vlan100 -o vlan200 -s 192.168.0.0/24 -d 192.168.2.0/24 \
            -m comment --comment TEL141-L4-route-100-200 -j ACCEPT
          iptables -C FORWARD -i vlan200 -o vlan100 -s 192.168.2.0/24 -d 192.168.0.0/24 \
            -m comment --comment TEL141-L4-route-100-200 -j ACCEPT
        fi
        for ID in 100 200; do
          if [[ $ID == 100 ]]; then NET=192.168.0; M=01; else NET=192.168.2; M=02; fi
          ip -4 addr show "vlan$ID"
          if ! is_static_vlan "$ID"; then
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
          fi
          if ! internet_enabled; then
            [[ ! -f $STATE/internet/$ID ]] || die "Hay permiso NAT registrado para VLAN $ID."
            NAT_RULES=$(iptables -t nat -S POSTROUTING)
            [[ $NAT_RULES != *"$NET.0/24"* ]] || die "NAT residual para $NET.0/24"
          else
            iptables -t nat -C POSTROUTING -s "$NET.0/24" -o ens3 \
              -m comment --comment "TEL141-L4-internet-$ID" -j MASQUERADE
          fi
        done
        iptables -t nat -vnL POSTROUTING
        ;;
      ofs) python3 "$HERE/helpers/check_ofs.py" ;;
    esac
    echo "VERIFICACION OK $ROLE actividad $ACTIVITY_ID"
    ;;
  routing_evidence)
    [[ $ROLE == server3 && $ACTIVITY_ID == 4 ]] || die 'Evidencia de rutas solo para server3/A4.'
    python3 "$HERE/helpers/firewall.py" verify 4
    COUNTERS=$(iptables -L TEL141_RF -v -n -x)
    printf '%s\n' "$COUNTERS"
    for PAIR in 'vlan100 vlan200' 'vlan200 vlan100'; do
      read -r IN OUT <<< "$PAIR"
      awk -v incoming="$IN" -v outgoing="$OUT" \
        '$3=="ACCEPT" && $6==incoming && $7==outgoing && $1>0 {ok=1} END {exit !ok}' <<< "$COUNTERS" \
        || die "No hay paquetes encaminados de $IN a $OUT."
    done
    echo ENRUTAMIENTO_BIDIRECCIONAL_CON_CONTADORES_OK
    ;;
  *) die 'Accion no admitida.' ;;
esac
