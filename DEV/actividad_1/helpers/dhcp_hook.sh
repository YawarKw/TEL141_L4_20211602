#!/bin/sh
# Hook udhcpc de los contenedores. Direcciones recibidas por DHCP, nunca estaticas.
set -eu
case "$1" in
  deconfig) ip -4 addr flush dev "$interface" ;;
  bound|renew)
    ifconfig "$interface" "$ip" netmask "$subnet" up
    set -- $router
    ip route replace default via "$1" dev "$interface"
    : > /etc/resolv.conf
    for nameserver in $dns; do
      printf 'nameserver %s\n' "$nameserver" >> /etc/resolv.conf
    done
    ;;
esac
