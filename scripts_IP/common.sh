#!/usr/bin/env bash
# Funciones compartidas. Bash 4+, Linux x86_64, Open vSwitch e iptables.
set -euo pipefail
export LC_ALL=C
STATE=/var/lib/tel141-l4
BASE="$STATE/images/cirros-0.5.1-x86_64-disk.img"
BR=br-int

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { local c; for c in "$@"; do command -v "$c" >/dev/null || die "Falta instalar $c"; done; }
begin() {
    (( EUID == 0 )) || die 'Ejecute con sudo o como root.'
    need ip ovs-vsctl flock
    umask 077
    mkdir -p "$STATE"/{networks,internet,vms,images}
    exec 9>"$STATE/lock"
    flock -x 9
}
vlan() { [[ $1 =~ ^[1-9][0-9]{0,3}$ ]] && (( $1 <= 4094 )) || die 'VLAN: entero entre 1 y 4094.'; }
name_ok() { [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9_-]{0,31}$ ]] || die 'Nombre: 1-32 letras, digitos, guion o guion bajo.'; }
if_ok() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,14}$ ]] || die "Interfaz invalida: $1"; }
port_ok() { [[ $1 =~ ^[1-9][0-9]{3,4}$ ]] && (( $1 >= 5900 && $1 <= 65535 )) || die 'Indique puerto TCP VNC entre 5900 y 65535 (ejemplo: 5901).'; }

ipnum() {
    local a b c d n
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "IPv4 invalida: $1"
    IFS=. read -r a b c d <<< "$1"
    for n in "$a" "$b" "$c" "$d"; do (( 10#$n <= 255 )) || die "IPv4 invalida: $1"; done
    printf '%s\n' "$(( (10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d ))"
}
iptext() { local n=$1; printf '%d.%d.%d.%d\n' "$((n>>24&255))" "$((n>>16&255))" "$((n>>8&255))" "$((n&255))"; }
cidr() {
    local addr p
    [[ $1 == */* ]] || die 'Falta prefijo CIDR.'
    addr=${1%/*}; p=${1##*/}
    [[ $p =~ ^([1-9]|[12][0-9]|30)$ ]] || die 'Prefijo admitido: /1 a /30.'
    PREFIX=$p; NETNUM=$(ipnum "$addr")
    MASKNUM=$(( (4294967295 << (32-PREFIX)) & 4294967295 ))
    (( (NETNUM & MASKNUM) == NETNUM )) || die 'Use la direccion de red, no una IP de host.'
    BROADNUM=$(( NETNUM | (4294967295 ^ MASKNUM) ))
    NETWORK="$(iptext "$NETNUM")/$PREFIX"
    MASK=$(iptext "$MASKNUM"); GW=$(iptext "$((NETNUM+1))"); DHCPIP=$(iptext "$((NETNUM+2))")
}
range_ok() {
    local a b
    [[ $1 == *,* ]] || die 'Rango DHCP: IP_INICIO,IP_FIN, sin espacios.'
    START=${1%,*}; END=${1#*,}
    a=$(ipnum "$START"); b=$(ipnum "$END")
    (( a >= NETNUM+3 && a <= b && b < BROADNUM )) || die 'Rango DHCP fuera de red o incluye red, gateway, servidor o broadcast.'
    START=$(iptext "$a"); END=$(iptext "$b")
}
bridge_exists() { ovs-vsctl br-exists "$1" || die "No existe el bridge $1"; }
network_exists() {
    [[ -f $STATE/networks/$1 ]] || die "Cree primero VLAN $1 con create_network_vlan.sh."
    ip link show "vlan$1" >/dev/null || die "No existe vlan$1; vuelva a crear la red tras reiniciar."
}
get_network() { head -n 1 "$STATE/networks/$1"; }
ns_exists() { ip netns list | awk '{print $1}' | grep -Fxq "$1"; }

# Reglas identificadas y repetibles: nunca se vacia el firewall del equipo.
rule_add() {
    local table=$1 chain=$2; shift 2
    if ! iptables -w -t "$table" -C "$chain" "$@" 2>/dev/null; then
        iptables -w -t "$table" -I "$chain" 1 "$@"
    fi
}
rule_del() {
    local table=$1 chain=$2; shift 2
    while iptables -w -t "$table" -C "$chain" "$@" 2>/dev/null; do
        iptables -w -t "$table" -D "$chain" "$@"
    done
}
internet_rules() {
    local action=$1 id=$2 net=$3 ext=$4 label="TEL141-L4-internet-$2"
    "$action" filter FORWARD -i "vlan$id" -o "$ext" -s "$net" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -m comment --comment "$label" -j ACCEPT
    "$action" filter FORWARD -i "$ext" -o "vlan$id" -d "$net" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "$label" -j ACCEPT
    "$action" nat POSTROUTING -s "$net" -o "$ext" -m comment --comment "$label" -j MASQUERADE
}
routing_rules() {
    local action=$1 a=$2 b=$3 na nb label
    (( a < b )) || { a=$3; b=$2; }
    na=$(get_network "$a"); nb=$(get_network "$b"); label="TEL141-L4-route-$a-$b"
    "$action" filter FORWARD -i "vlan$a" -o "vlan$b" -s "$na" -d "$nb" -m comment --comment "$label" -j ACCEPT
    "$action" filter FORWARD -i "vlan$b" -o "vlan$a" -s "$nb" -d "$na" -m comment --comment "$label" -j ACCEPT
}
init_bridge() {
    local iface current
    for iface in "$@"; do
        if_ok "$iface"; [[ $iface != "$BR" && $iface != lo ]] || die 'Use interfaces de datos.'
        ip link show "$iface" >/dev/null || die "No existe $iface"
        [[ -z $(ip -o addr show dev "$iface" scope global) ]] || die "$iface tiene IP; no conecte la interfaz de gestion al OVS."
        current=$(ovs-vsctl iface-to-br "$iface" 2>/dev/null || true)
        [[ -z $current || $current == "$BR" ]] || die "$iface pertenece a $current."
    done
    ovs-vsctl --may-exist add-br "$BR"
    ip link set "$BR" up
    for iface in "$@"; do
        ovs-vsctl --may-exist add-port "$BR" "$iface"
        ovs-vsctl clear Port "$iface" tag trunks
        ovs-vsctl set Port "$iface" vlan_mode=trunk
        ip link set "$iface" up
    done
}
# Identifica el proceso antes de enviarle una senal, incluso con PID obsoleto.
stop_owned() {
    local file=$1 binary=$2 token=$3 pid arg found=0 exe i
    [[ -s $file ]] || return 0
    read -r pid < "$file"
    [[ $pid =~ ^[1-9][0-9]*$ ]] || die "PID invalido en $file"
    if [[ ! -d /proc/$pid ]]; then rm -f "$file"; return 0; fi
    exe=$(readlink "/proc/$pid/exe")
    [[ ${exe##*/} == "$binary" ]] || die 'PID reutilizado por otro programa; no se detuvo.'
    while IFS= read -r -d '' arg; do [[ $arg != "$token" ]] || found=1; done < "/proc/$pid/cmdline"
    (( found )) || die 'El PID no corresponde al recurso solicitado.'
    kill -TERM "$pid"
    for ((i=0;i<50;i++)); do
        if ! kill -0 "$pid" 2>/dev/null || [[ $(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true) == Z ]]; then
            rm -f "$file"; return 0
        fi
        sleep 0.2
    done
    die 'El proceso no termino; se conservaron sus recursos.'
}
