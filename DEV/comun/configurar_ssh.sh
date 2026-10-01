#!/usr/bin/env bash
# Ejecutar como ubuntu EN SERVER4. La clave privada permanece aqui.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/config.sh"
[[ $(hostname -s) == server4 ]] || { echo 'Ejecute este archivo desde server4.' >&2; exit 1; }
[[ $(id -un) == "$SSH_USER" ]] || { echo 'Ejecute como ubuntu, sin sudo.' >&2; exit 1; }
install -d -m 700 "$HOME/.ssh"
if [[ ! -f $SSH_KEY ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N '' -C 'TEL141-20211602-server4'
fi
for ROLE in server1 server2 server3 ofs; do
  echo "Instalando la clave PUBLICA de server4 en $ROLE (${HOSTS[$ROLE]})."
  ssh-copy-id -i "$SSH_KEY.pub" -p "$SSH_PORT" "$SSH_USER@${HOSTS[$ROLE]}"
  ssh -i "$SSH_KEY" -p "$SSH_PORT" -o IdentitiesOnly=yes -o BatchMode=yes \
    "$SSH_USER@${HOSTS[$ROLE]}" 'hostname; sudo -n true'
done
echo 'SSH desde server4 y sudo sin interaccion: OK.'
