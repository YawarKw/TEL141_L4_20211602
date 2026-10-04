#!/usr/bin/env bash
# Funciones sin efectos de red; ACTIVITY_ID se valida en los puntos de entrada.
is_static_vlan() {
    [[ $ACTIVITY_ID == 2 || ( $ACTIVITY_ID == 4 && $1 == 100 ) ]]
}
internet_enabled() {
    [[ $ACTIVITY_ID == 1 || $ACTIVITY_ID == 2 ]]
}
