#!/usr/bin/env bash
# Uso: sudo ./init_worker.sh INTERFAZ_DATOS [OTRA_INTERFAZ...]
source "$(dirname "$(readlink -f "$0")")/common.sh"
(( $# >= 1 )) || die 'Uso: init_worker.sh INTERFAZ [INTERFAZ...]'
begin
init_bridge "$@"
printf 'Worker listo: br-int y enlaces trunk activos.\n'
