#!/usr/bin/env bash
# Uso: sudo ./delete_vm.sh NOMBRE_VM OVS VLAN PUERTO_TCP_VNC
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 4 )) || die 'Uso: delete_vm.sh NOMBRE_VM OVS VLAN PUERTO_TCP_VNC'
name_ok "$1"; if_ok "$2"; vlan "$3"; port_ok "$4"
VM=$1; OVS=$2; ID=$3; PORT=$4
begin; need find
DIR="$STATE/vms/$VM"
[[ -f $DIR/metadata ]] || die 'VM no registrada por estos scripts.'
mapfile -t META < "$DIR/metadata"
[[ ${META[0]} == "$OVS" && ${META[1]} == "$ID" && ${META[2]} == "$PORT" ]] || die 'Los parametros no coinciden con la VM registrada.'
TAP=${META[3]}; if_ok "$TAP"
stop_owned "$DIR/qemu.pid" qemu-system-x86_64 "file=$DIR/disk.qcow2,format=qcow2,if=virtio"
ovs-vsctl --if-exists del-port "$OVS" "$TAP"
if ip link show "$TAP" &>/dev/null; then ip tuntap del dev "$TAP" mode tap; fi
rm -f -- "$DIR/disk.qcow2" "$DIR/metadata" "$DIR/qemu.pid"
rmdir -- "$DIR"
# Todas las VMs gestionadas usan esta base privada; no se comparte fuera de STATE.
if [[ -z $(find "$STATE/vms" -type f -name '*.qcow2' -print -quit) ]]; then
    rm -f -- "$BASE"
    printf 'Imagen base privada eliminada: no quedan discos delta.\n'
fi
printf 'VM %s y recursos asociados eliminados.\n' "$VM"
