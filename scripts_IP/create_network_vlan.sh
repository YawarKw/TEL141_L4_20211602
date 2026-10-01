#!/usr/bin/env bash
# Uso: sudo ./create_network_vlan.sh VLAN RED_CIDR {si|no} [INICIO,FIN]
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# == 3 || $# == 4 )) || die 'Uso: create_network_vlan.sh VLAN RED/CIDR si|no [INICIO,FIN]'
vlan "$1"; cidr "$2"
ID=$1; MODE=$3; RANGE=${4:-}
case "$MODE" in
    si) (( $# == 4 )) || die 'Indique rango DHCP.'; range_ok "$RANGE";;
    no) (( $# == 3 )) || die 'DHCP no: no incluya rango.';;
    *) die 'DHCP debe ser si o no.';;
esac
begin; bridge_exists "$BR"
[[ $MODE == no ]] || need dnsmasq
GWIF="vlan$ID"; NS="ns-dhcp-$ID"; VH="dh${ID}h"; VN="dh${ID}n"
RECORD="$STATE/networks/$ID"; CONF="$STATE/networks/dnsmasq-$ID.conf"; PID="$STATE/networks/dnsmasq-$ID.pid"
# No se renumera una red existente ni se invade un recurso ajeno.
if [[ -f $RECORD ]]; then
    [[ $(head -n 1 "$RECORD") == "$NETWORK" ]] || die 'VLAN ya asociada a otra red.'
else
    ! ip link show "$GWIF" &>/dev/null || die "$GWIF ya existe fuera de este proyecto."
    ! ns_exists "$NS" || die "$NS ya existe fuera de este proyecto."
    ! ip link show "$VH" &>/dev/null || die "$VH ya existe."
    ! ip link show "$VN" &>/dev/null || die "$VN ya existe."
fi
# Una interfaz del host no debe introducir otra subred superpuesta.
while read -r other; do
    [[ -n $other ]] || continue
    overlap=$( (cidr "$other"; printf '%s %s' "$NETNUM" "$BROADNUM") ) || die 'No se pudo validar una red existente.'
    read -r lo hi <<< "$overlap"
    (( NETNUM > hi || BROADNUM < lo )) || die "La red se superpone con $other."
done < <(ip -o -4 route show scope link | awk -v dev="$GWIF" '$0 !~ ("dev " dev "( |$)") && $1 ~ /\// {print $1}')
printf '%s\n%s\n%s\n' "$NETWORK" "$MODE" "$RANGE" > "$RECORD"
ovs-vsctl --may-exist add-port "$BR" "$GWIF" -- set Interface "$GWIF" type=internal -- set Port "$GWIF" tag="$ID" vlan_mode=access
ip addr replace "$GW/$PREFIX" dev "$GWIF"
ip link set "$GWIF" up
stop_owned "$PID" dnsmasq "--conf-file=$CONF"
if [[ $MODE == no ]]; then
    if ns_exists "$NS"; then
        [[ -z $(ip netns pids "$NS") ]] || die 'Hay procesos ajenos en el namespace.'
        ip netns del "$NS"
    fi
    ovs-vsctl --if-exists del-port "$BR" "$VH"
    if ip link show "$VH" &>/dev/null; then ip link del "$VH"; fi
    rm -f "$CONF"
    printf 'VLAN %s: gateway %s/%s; DHCP deshabilitado.\n' "$ID" "$GW" "$PREFIX"
    exit 0
fi
ns_exists "$NS" || ip netns add "$NS"
if ! ip link show "$VH" &>/dev/null; then
    ip link add "$VH" type veth peer name "$VN"
    ip link set "$VN" netns "$NS"
fi
ovs-vsctl --may-exist add-port "$BR" "$VH" -- set Port "$VH" tag="$ID" vlan_mode=access
ip link set "$VH" up
ip -n "$NS" link set lo up
ip -n "$NS" addr replace "$DHCPIP/$PREFIX" dev "$VN"
ip -n "$NS" link set "$VN" up
ip -n "$NS" route replace default via "$GW"
cat > "$CONF" <<EOF
interface=$VN
bind-interfaces
port=0
dhcp-authoritative
dhcp-range=$START,$END,$MASK,12h
dhcp-option=3,$GW
dhcp-option=6,8.8.8.8
dhcp-leasefile=$STATE/networks/dnsmasq-$ID.leases
pid-file=$PID
log-facility=$STATE/networks/dnsmasq-$ID.log
log-dhcp
user=root
EOF
dnsmasq --test --conf-file="$CONF"
# Cerrar el descriptor de flock en el demonio para no bloquear llamadas posteriores.
ip netns exec "$NS" dnsmasq --conf-file="$CONF" 9>&-
printf 'VLAN %s: gateway %s; DHCP %s en %s; rango %s.\n' "$ID" "$GW" "$DHCPIP" "$NS" "$RANGE"
