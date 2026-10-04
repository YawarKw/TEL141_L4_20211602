#!/usr/bin/env bash
# Uso: sudo ./create_vm.sh NOMBRE_VM OVS VLAN PUERTO_TCP_VNC
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 4 )) || die 'Uso: create_vm.sh NOMBRE_VM OVS VLAN PUERTO_TCP_VNC'
name_ok "$1"; if_ok "$2"; vlan "$3"; port_ok "$4"
VM=$1; OVS=$2; ID=$3; PORT=$4; DISPLAY_NUM=$((PORT-5900))
begin; need qemu-img qemu-system-x86_64 ss sha256sum curl
bridge_exists "$OVS"
[[ -r /dev/kvm && -w /dev/kvm ]] || die '/dev/kvm no disponible: habilite KVM o virtualizacion anidada.'
[[ ! -e $STATE/vms/$VM ]] || die 'VM o recursos ya existentes. Use delete_vm.sh antes de recrearla.'
[[ -z $(ss -H -ltn "sport = :$PORT") ]] || die "Puerto $PORT ocupado."
HASH=$(printf '%s' "$VM" | sha256sum); HASH=${HASH:0:12}; TAP="t$HASH"
! ip link show "$TAP" &>/dev/null || die "TAP $TAP ya existe."
if [[ ! -s $BASE ]]; then
    LOCAL_IMAGE="$PWD/$(basename "$BASE")"
    if [[ -s $LOCAL_IMAGE ]]; then
        cp -- "$LOCAL_IMAGE" "$BASE.part"
    else
        curl --fail --location --retry 3 --output "$BASE.part" 'https://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img'
    fi
    qemu-img info -f qcow2 "$BASE.part" >/dev/null
    mv -- "$BASE.part" "$BASE"
    chmod 444 "$BASE"
fi
qemu-img info -f qcow2 "$BASE" >/dev/null
DIR="$STATE/vms/$VM"; mkdir "$DIR"
printf '%s\n%s\n%s\n%s\n' "$OVS" "$ID" "$PORT" "$TAP" > "$DIR/metadata"
# El registro permite retirar recursos incluso si QEMU no consigue arrancar.
qemu-img create -f qcow2 -F qcow2 -b "$BASE" "$DIR/disk.qcow2"
ip tuntap add dev "$TAP" mode tap
ovs-vsctl add-port "$OVS" "$TAP" -- set Port "$TAP" tag="$ID" vlan_mode=access
ip link set "$TAP" up
MACHINE_ID=$(cat /etc/machine-id)
MAC_HASH=$(printf '%s:%s' "$MACHINE_ID" "$VM" | sha256sum)
MAC="02:${MAC_HASH:0:2}:${MAC_HASH:2:2}:${MAC_HASH:4:2}:${MAC_HASH:6:2}:${MAC_HASH:8:2}"
if [[ -n ${TEL141_MAC:-} ]]; then
    [[ $TEL141_MAC =~ ^02(:[0-9a-fA-F]{2}){5}$ ]] || die 'MAC local invalida.'
    MAC=$TEL141_MAC
fi
SERIAL_ARGS=(-serial none)
if [[ ${TEL141_SERIAL:-0} == 1 ]]; then
    SERIAL_ARGS=(-serial "unix:$DIR/serial.sock,server,nowait")
fi
qemu-system-x86_64 -name "$VM" -enable-kvm -m 512 -smp 1 \
    -drive "file=$DIR/disk.qcow2,format=qcow2,if=virtio" \
    -netdev "tap,id=net0,ifname=$TAP,script=no,downscript=no" \
    -device "e1000,netdev=net0,mac=$MAC" \
    -vnc "127.0.0.1:$DISPLAY_NUM" -monitor none "${SERIAL_ARGS[@]}" \
    -daemonize -pidfile "$DIR/qemu.pid" 9>&- 8>&-
printf 'VM %s: TAP %s, VLAN %s, VNC local 127.0.0.1:%s (display :%s).\n' "$VM" "$TAP" "$ID" "$PORT" "$DISPLAY_NUM"
