# TEL141 — Lab4, reporte final: actividades 1, 2 y 3


Esta entrega agrega las actividades 2 y 3 y unifica la limpieza de las tres actividades. Sustituye los puntos de entrada anteriores por una versión que reconoce los recursos de todos estos escenarios. No incluye la actividad 4.

## Escenarios

| Actividad | Direcciones de los clientes | DHCP | Internet de los clientes | Comunicación entre VLANs |
|---|---|---|---|---|
| 1 | Reservas entregadas por DHCP | Sí | Sí | Bloqueada |
| 2 | Configuración estática | No | Sí | Bloqueada |
| 3 | Reservas entregadas por DHCP | Sí | Bloqueado | Bloqueada |

**Solo una actividad queda desplegada a la vez.** Cada `deploy` limpia los recursos identificados de la actividad anterior y recrea el escenario solicitado. Guarda las evidencias de la actividad 2 antes de ejecutar la 3.

## Topología y direcciones

| Nodo | Gestión | Función |
|---|---|---|
| server4 | 10.0.10.4 | Orquestador SSH |
| server1 | 10.0.10.1 | OVS `br-int` y dos contenedores mediante veth |
| server2 | 10.0.10.2 | OVS `br-int` y dos VMs CirrOS mediante TAP |
| server3 | 10.0.10.3 | Gateways, firewall, DHCP cuando corresponde y NAT cuando corresponde |
| ofs | 10.0.10.5 | Switch existente: se inspecciona, no se reconfigura |

En server1–3, `ens3` corresponde a gestión/salida y `ens4` a datos hacia OFS. La orquestación usa puerto SSH **22** entre nodos. Los puertos 5801–5805 corresponden al acceso desde tu PC mediante el gateway.

| VLAN | Red | Gateway | Contenedor en server1 | VM en server2 | DHCP en server3, cuando aplica |
|---|---|---|---|---|---|
| 100 | 192.168.0.0/24 | 192.168.0.1 | 192.168.0.11 | 192.168.0.12 | 192.168.0.2 |
| 200 | 192.168.2.0/24 | 192.168.2.1 | 192.168.2.11 | 192.168.2.12 | 192.168.2.2 |

En las actividades 1 y 3, `.11` y `.12` son reservas DHCP por MAC dentro del rango `.11`–`.15`. En la actividad 2 esas mismas direcciones se asignan estáticamente. Los gateways usan puertos internos OVS `vlan100` y `vlan200`, equivalentes funcionales a `gw_vlan100` y `gw_vlan200` del dibujo.

Los nombres llevan el número de actividad: `a2-cont100`, `a2-cont200`, `a2-vm100` y `a2-vm200`; en la actividad 3 empiezan con `a3-`. Las VMs usan CirrOS 0.5.1, 512 MiB y un vCPU. Los contenedores usan Alpine 3.22 sin red Docker automática.

## Archivos incorporados en el repositorio


| Ruta | Contenido |
|---|---|
| `DEV/actividad_1/actividad1.sh` | Entrada para actividad 1, compatible con el nuevo conjunto |
| `DEV/actividad_2/actividad2.sh` | Entrada para actividad 2 |
| `DEV/actividad_3/actividad3.sh` | Entrada para actividad 3 |
| `DEV/comun/orquestar.sh` | Principal compartido en Bash; secuencia SSH desde server4 |
| `DEV/comun/config.sh` | Inventario, clave SSH, imagen y destinos de prueba |
| `DEV/comun/configurar_ssh.sh` | Configuración de acceso por clave desde server4 |
| `DEV/comun/node.sh` | Despliegue y verificación remotos |
| `DEV/comun/helpers/` | Limpieza selectiva, firewall, contenedores y consola de VMs |
| `DEV/comun/tests/` | Pruebas locales simuladas y su resultado |
| `scripts_IP/` | Scripts reutilizados del informe previo |


## Preparación en server4


```powershell
scp -P 5804 .\TEL141_L4_20211602_RF_A123.zip ubuntu@10.20.11.46:~/
ssh -p 5804 ubuntu@10.20.11.46
```

Usa el gateway asignado si es distinto de `10.20.11.46`. Dentro de server4:

```bash
hostname
sudo apt-get update
sudo apt-get install -y unzip openssh-client
unzip TEL141_L4_20211602_RF_A123.zip
cd ~/TEL141_L4_20211602_RF_A123
```

Si incorporaste los archivos a tu repositorio en server4, entra en su raíz en lugar de la carpeta del ZIP. No es necesario mantener dos copias de trabajo.

Configura acceso y dependencias una vez:

```bash
bash DEV/comun/configurar_ssh.sh
bash DEV/actividad_2/actividad2.sh deps
```

Se reutiliza la clave `~/.ssh/id_ed25519_tel141_s4` de la primera entrega. Si todavía no existe, se genera una clave dedicada sin frase de paso. La instalación inicial puede solicitar la contraseña de `ubuntu` en cada nodo y confirmar su huella SSH. La guía indica `ubuntu` como contraseña inicial, si no fue cambiada. La clave privada permanece en server4.

La cuenta debe permitir `sudo -n` en los destinos. Si falla esa comprobación, revisa el acceso administrativo previsto con el responsable del laboratorio. El script no modifica sudoers. `deps` instala paquetes en server1–3; no altera OFS.

## Ejecutar la actividad 2

Primero, se inspecciona sin limpiar:

```bash
bash DEV/actividad_2/actividad2.sh plan
```

Si termina correctamente, despliega:

```bash
bash DEV/actividad_2/actividad2.sh deploy
echo "Codigo de salida actividad 2: $?"
```

La automatización retira los DHCP anteriores de laboratorio, crea ambas redes con la opción `no` de `create_network_vlan.sh` y habilita NAT. Los contenedores reciben su IP, gateway y DNS directamente. Las VMs arrancan desde una imagen nueva y luego reciben la configuración estática por consola serie: se detienen sus clientes DHCP, se escribe `/etc/network/interfaces` y se aplica la dirección.

CirrOS puede intentar DHCP durante su arranque predeterminado; al finalizar la configuración estática se exige que no queden clientes DHCP activos. No se utiliza una concesión para asignar las IP de esta actividad.

Además de comprobar que no hay DHCP de laboratorio en server3, se realiza una solicitud temporal desde cada contenedor para detectar un servicio residual en su VLAN. Esa prueba utiliza un hook que no modifica la IP estática y termina al concluir. Si consigue una concesión, se considera fallo.

Para repetir las comprobaciones sin recrear recursos:

```bash
bash DEV/actividad_2/actividad2.sh verify
echo "Codigo de salida verificacion: $?"
```

Resultados esperados: IP estática y ruta correctas; ping al gateway, al otro cliente de la misma VLAN y a Internet; DNS operativo; ping entre VLANs fallido; `SIN_DHCP_SERVER3_OK`, `SIN_OFERTAS_DHCP_OK`, `INTERNET_OK`, `AISLAMIENTO_OK` y `PASS` al completar todo.

**Guarda estas evidencias antes del siguiente despliegue.**

## Ejecutar la actividad 3

```bash
bash DEV/actividad_3/actividad3.sh plan
```

Si el plan termina correctamente:

```bash
bash DEV/actividad_3/actividad3.sh deploy
echo "Codigo de salida actividad 3: $?"
```

El despliegue limpia la actividad anterior, crea DHCP para ambas VLAN y elimina los permisos NAT específicos anteriores. Instala primero en FORWARD una cadena que bloquea el tráfico encaminado de los clientes, incluidos paquetes de conexiones anteriores. La comunicación local dentro de cada VLAN y DHCP permanecen disponibles.

**La restricción de Internet se aplica a los clientes del laboratorio.** Server3 conserva la conectividad de gestión por `ens3`. El parámetro global `ip_forward` permanece habilitado; la prohibición se aplica mediante reglas explícitas para las redes del slice. Esto permite conservar el comportamiento de gestión del host y comprobar la política del laboratorio por separado.

La validación comprueba primero que server3 sí puede alcanzar el destino externo y que la cadena de protección es la primera regla de FORWARD. Después exige conectividad local desde cada cliente y fallo del ping externo y del ping inter-VLAN. También revisa las concesiones DHCP y las reglas exactas del firewall. No basta con observar un ping fallido.

```bash
bash DEV/actividad_3/actividad3.sh verify
echo "Codigo de salida verificacion: $?"
```

Resultados esperados: concesiones `.11` y `.12`, ping al gateway y al vecino de la misma VLAN correctos, ping a Internet fallido y ping entre VLANs fallido. Deben aparecer `INTERNET_HOST_OK`, `INTERNET_BLOQUEADO_OK`, `AISLAMIENTO_OK` y finalmente `PASS`. El DNS externo anunciado por DHCP tampoco será accesible desde los clientes; no se exige resolución externa en esta actividad.

El código final de la automatización debe ser **0** en ambas actividades: los pings que deben fallar son comprobaciones negativas esperadas y se procesan dentro del script.

## Limpieza y cambio de actividad

Cada `deploy` sigue este orden: comprobación de los cuatro destinos → preparación de imágenes → limpieza de server1, server2 y server3 → despliegue en server3, server2 y server1 → espera de los clientes → verificación.

Reconoce los recursos del Lab3, de la primera entrega de A1 y de las tres actividades actuales por sus nombres y enlaces a bridges. Incluye bridges OVS/Linux conocidos, TAP, veth, procesos QEMU asociados, contenedores identificados, namespaces DHCP y reglas de firewall del laboratorio.

Antes de limpiar exige que `ens3` conserve la IP y ruta de gestión esperadas. No limpia OFS ni utiliza `pkill` general ni vacía todo iptables. Si encuentra un recurso ambiguo que impide validar la operación, aborta y muestra el motivo.

Conserva inventarios, firewall anterior y discos gestionados en `/var/lib/tel141-a1-backups/ID_DE_EJECUCION/` de cada servidor. El nombre del directorio se mantiene por compatibilidad con la primera entrega. Conserva la base QCOW2 y deja los discos antiguos externos en su ubicación. Los sistemas de archivos de los contenedores retirados no se respaldan; sus volúmenes no se eliminan. No existe restauración automática del escenario anterior.

Para retirar el escenario sin recrearlo:

```bash
bash DEV/actividad_3/actividad3.sh clean
```

Para volver a la actividad 1 se utiliza el punto de entrada de **este paquete**:

```bash
bash DEV/actividad_1/actividad1.sh deploy
```

No se ejecuta simultáneamente las copias antiguas y nuevas. La nueva orden `verify` exige el registro de actividad que genera este paquete; una A1 desplegada con la versión anterior debe recrearse para verificarla con esta versión.

## Evidencias y entrega

Los registros quedan separados en `DEV/actividad_2/evidencias/FECHA-PID/` y `DEV/actividad_3/evidencias/FECHA-PID/`. La limpieza remota no borra estos registros de server4.

| Evidencia | Archivo principal |
|---|---|
| Ejecución desde server4, orden y resultado | `orquestacion.log`, `resultado.txt` |
| Recursos antes de limpiar | `serverN-check.log` |
| Limpieza y creación | `serverN-clean.log`, `serverN-deploy.log` |
| Configuración estática de las VMs de A2 | `server2-ready.log` |
| IP y conectividad de ambos contenedores | `server1-verify.log` |
| IP y conectividad dentro de ambas VMs | `server2-verify.log` |
| DHCP/ausencia de DHCP, NAT y firewall | `server3-verify.log` |
| Switch de tránsito | `ofs-verify.log` |

Adjunta capturas reales del comando en server4, las pruebas representativas de cada VLAN y la finalización con `PASS` y código 0. Si aparece `FAILED`, conserva el registro para corregir la causa; no lo presentes como ejecución exitosa. Un fallo posterior a la limpieza puede dejar un despliegue parcial; al corregirlo, `deploy` vuelve a inventariar y recrear.

Si necesitas VNC, abre desde tu PC el túnel hacia server2:

```bash
ssh -p 5802 -N -L 30011:127.0.0.1:5901 -L 30012:127.0.0.1:5902 ubuntu@10.20.11.46
```

Usa `127.0.0.1`, puerto 30011 para VLAN 100 o 30012 para VLAN 200. Credenciales CirrOS: `cirros` / `gocubsgo`. El acceso VNC es para observación; el aprovisionamiento lo realiza server4.

Incorporar código y evidencias revisados:

```bash
git status --short
git add scripts_IP DEV
git diff --cached --stat
git commit -m "Automatiza actividades 2 y 3 y unifica limpieza de Lab4"
git push
```

No subas claves privadas ni discos de las VMs. La carpeta de evidencias sí debe acompañar el trabajo.

