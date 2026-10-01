#!/usr/bin/env bash
# Principal A1: comprobacion -> recursos -> limpieza -> despliegue -> evidencias.
# Uso (server4): bash DEV/actividad_1/actividad1.sh plan|deps|deploy|verify|clean
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
source "$HERE/config.sh"
MODE=${1:-plan}
case "$MODE" in plan|deps|deploy|verify|clean) ;; *) echo 'Uso: actividad1.sh plan|deps|deploy|verify|clean' >&2; exit 2;; esac
[[ $(hostname -s) == server4 ]] || { echo 'Todo despliegue debe iniciarse desde server4.' >&2; exit 1; }
[[ $(id -un) == "$SSH_USER" ]] || { echo 'Ejecute como ubuntu; el script usa sudo remoto.' >&2; exit 1; }
[[ -r $SSH_KEY ]] || { echo 'Primero ejecute configurar_ssh.sh en server4.' >&2; exit 1; }
[[ $INTERNET_TEST_IP =~ ^[0-9.]+$ && $DNS_TEST_NAME =~ ^[A-Za-z0-9.-]+$ ]] || exit 2
exec 7>"$HERE/.orquestacion.lock"
flock -n 7 || { echo 'Ya hay otra ejecucion en server4.' >&2; exit 1; }
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
EVIDENCE="$HERE/evidencias/$RUN_ID"
mkdir -p "$EVIDENCE"
exec > >(tee "$EVIDENCE/orquestacion.log") 2>&1
SSH=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
declare -A STAGES
FINISHED=0
finish() {
  local rc=$?
  if (( rc!=0 || ! FINISHED )); then
    printf 'FALLO: ejecucion interrumpida; revisar %s\n' "$EVIDENCE"
    printf 'FAILED\n' > "$EVIDENCE/resultado.txt"
  fi
  for role in "${!STAGES[@]}"; do
    "${SSH[@]}" "$SSH_USER@${HOSTS[$role]}" "rm -rf -- '${STAGES[$role]}'" >/dev/null 2>&1 || true
  done
}
trap finish EXIT
echo "ACTIVIDAD 1 | $MODE | $RUN_ID | origen $(hostname -s)"
cp "$HERE/config.sh" "$EVIDENCE/config_utilizada.sh"
for ROLE in server1 server2 server3 ofs; do
  [[ ${HOSTS[$ROLE]} =~ ^[A-Za-z0-9.-]+$ ]] || exit 2
  TARGET="$SSH_USER@${HOSTS[$ROLE]}"
  REMOTE_HOST=$("${SSH[@]}" "$TARGET" 'hostname -s; sudo -n true')
  [[ $REMOTE_HOST == "$ROLE" ]] || { echo "Identidad inesperada: $TARGET -> $REMOTE_HOST"; exit 1; }
  DIR=$("${SSH[@]}" "$TARGET" 'mktemp -d /tmp/tel141-a1.XXXXXXXX')
  [[ $DIR =~ ^/tmp/tel141-a1\.[A-Za-z0-9]+$ ]] || exit 1
  STAGES[$ROLE]=$DIR
  tar -C "$ROOT" -czf - scripts_IP DEV/actividad_1/node.sh DEV/actividad_1/helpers \
    | "${SSH[@]}" "$TARGET" "tar -xzf - -C '$DIR'"
done
remote() {
  local role=$1 action=$2 command
  printf -v command '%q ' sudo -n bash "${STAGES[$role]}/DEV/actividad_1/node.sh" \
    "$action" "$role" "$RUN_ID" "$DOCKER_IMAGE" "$INTERNET_TEST_IP" "$DNS_TEST_NAME"
  echo "[$role] $action"
  "${SSH[@]}" "$SSH_USER@${HOSTS[$role]}" "$command" 2>&1 | tee "$EVIDENCE/$role-$action.log"
}
if [[ $MODE == deps ]]; then
  # OFS ya viene provisto: no se instalan servicios ni se altera su configuracion.
  for ROLE in server1 server2 server3; do remote "$ROLE" deps; done
  FINISHED=1; echo DEPENDENCIAS_OK > "$EVIDENCE/resultado.txt"; exit 0
fi
if [[ $MODE == plan || $MODE == deploy || $MODE == clean ]]; then
  ERRORS=0
  for ROLE in server1 server2 server3 ofs; do
    remote "$ROLE" check || ERRORS=$((ERRORS+1))
  done
  (( ERRORS==0 )) || { echo 'Precomprobacion fallida. NO se limpio la topologia.'; exit 1; }
fi
if [[ $MODE == plan ]]; then
  FINISHED=1; echo PLAN_OK > "$EVIDENCE/resultado.txt"
  echo "Plan terminado sin cambios de topologia: $EVIDENCE"; exit 0
fi
if [[ $MODE == deploy ]]; then
  # Descargar/validar antes de retirar la topologia anterior.
  remote server1 assets
  remote server2 assets
fi
if [[ $MODE == deploy || $MODE == clean ]]; then
  for ROLE in server1 server2 server3; do remote "$ROLE" clean; done
fi
if [[ $MODE == clean ]]; then
  FINISHED=1; echo LIMPIEZA_OK > "$EVIDENCE/resultado.txt"; exit 0
fi
if [[ $MODE == deploy ]]; then
  for ROLE in server3 server2 server1; do remote "$ROLE" deploy; done
  remote server1 ready
  remote server2 ready
fi
for ROLE in server1 server2 server3 ofs; do remote "$ROLE" verify; done
FINISHED=1
printf 'PASS: 4 clientes con DHCP; misma VLAN comunicada; Internet y DNS; VLAN 100 y 200 aisladas.\n' \
  | tee "$EVIDENCE/resultado.txt"
echo "Evidencias guardadas en $EVIDENCE"
