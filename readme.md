# TEL141 Laboratorio 4

Edgar Diaz Zevillanos / 20211602. 

Implementación en Bash de los nueve scripts de la actividad 2 del informe previo, y las 4 actividades del reporte final. `scripts/common.sh` es una biblioteca compartida que permanece junto a los nueve scripts. 
A continuación una guía para el uso de estos scripts:

## Escenarios

| Actividad | Direcciones de los clientes | DHCP | Internet de los clientes | Comunicación entre VLANs |
|---|---|---|---|---|
| 1 | Reservas entregadas por DHCP | Sí | Sí | Bloqueada |
| 2 | Configuración estática | No | Sí | Bloqueada |
| 3 | Reservas entregadas por DHCP | Sí | Bloqueado | Bloqueada |
| 4 | VLAN 100 estática; VLAN 200 por DHCP | Solo VLAN 200 | Bloqueado | Permitida en ambos sentidos |

**Solo una actividad queda desplegada a la vez.** Cada `deploy` limpia los recursos identificados de la actividad anterior y recrea el escenario solicitado. Guarda las evidencias de cada actividad antes de ejecutar la siguiente.

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

En las actividades 1 y 3, `.11` y `.12` son reservas DHCP por MAC dentro del rango `.11`–`.15`. En la actividad 2 esas mismas direcciones se asignan estáticamente. En la actividad 4, VLAN 100 usa configuración estática y VLAN 200 usa las reservas DHCP. Los gateways usan puertos internos OVS `vlan100` y `vlan200`, equivalentes funcionales a `gw_vlan100` y `gw_vlan200` del dibujo.

Los nombres llevan el número de actividad: `a2-cont100`, `a2-cont200`, `a2-vm100` y `a2-vm200`; en la actividad 3 empiezan con `a3-` y en la 4 con `a4-`. Las VMs usan CirrOS 0.5.1, 512 MiB y un vCPU. Los contenedores usan Alpine 3.22 sin red Docker automática.

## Archivos en el repositorio

| Ruta | Contenido |
|---|---|
| `DEV/actividad_1/actividad1.sh` | Entrada para actividad 1, compatible con el nuevo conjunto |
| `DEV/actividad_2/actividad2.sh` | Entrada para actividad 2 |
| `DEV/actividad_3/actividad3.sh` | Entrada para actividad 3 |
| `DEV/actividad_4/actividad4.sh` | Entrada para actividad 4 |
| `DEV/actividad_N/readme.md` | Instrucciones breves del escenario correspondiente |
| `DEV/comun/orquestar.sh` | Principal compartido en Bash; secuencia SSH desde server4 |
| `DEV/comun/config.sh` | Inventario, clave SSH, imagen y destinos de prueba |
| `DEV/comun/configurar_ssh.sh` | Configuración de acceso por clave desde server4 |
| `DEV/comun/node.sh` | Despliegue y verificación remotos |
| `DEV/comun/helpers/` | Limpieza selectiva, firewall, contenedores y consola de VMs |
| `DEV/comun/tests/` | Pruebas locales simuladas y su resultado |
| `scripts_IP/` | Scripts reutilizados del informe previo |


## Preparación en server4

Considerando la descarga del repositorio "TEL141_L4_20211602-main":
```powershell
scp -P 5804 .\TEL141_L4_20211602-main.zip ubuntu@10.20.11.46:~/
ssh -p 5804 ubuntu@10.20.11.46
```

En ubuntu:

```bash
hostname
sudo apt-get update
sudo apt-get install -y unzip openssh-client
unzip TEL141_L4_20211602-main.zip
cd ~/TEL141_L4_20211602-main
```

Configuración de acceso y dependencias :

```bash
bash DEV/comun/configurar_ssh.sh
bash DEV/actividad_4/actividad4.sh deps
```

Se reutiliza la clave `~/.ssh/id_ed25519_tel141_s4` de la primera entrega. Si todavía no existe, se genera una clave dedicada sin frase de paso. La instalación inicial puede solicitar la contraseña de `ubuntu` en cada nodo y confirmar su huella SSH. La guía indica `ubuntu` como contraseña inicial, si no fue cambiada. La clave privada permanece en server4.

La cuenta debe permitir `sudo -n` en los destinos. Si falla esa comprobación, revisa el acceso administrativo previsto con el responsable del laboratorio. El script no modifica sudoers. `deps` instala paquetes en server1–3; no altera OFS.

## Ejecutar la actividad 1


```bash
bash DEV/actividad_1/actividad1.sh plan
```

Si el plan termina correctamente:

```bash
bash DEV/actividad_1/actividad1.sh deploy
echo "Codigo de salida actividad 1: $?"
```

Se habilita DHCP y NAT para ambas VLAN. Se exige comunicación dentro de cada VLAN, acceso a Internet y DNS desde los cuatro clientes, y bloqueo entre VLAN 100 y 200. Para repetir solo las comprobaciones:

```bash
bash DEV/actividad_1/actividad1.sh verify
```

Captura de evidencias en el word.

## Ejecutar la actividad 2


```bash
bash DEV/actividad_2/actividad2.sh plan
```

Si termina correctamente, se despliega:

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

Captura de evidencias en el word.

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

Captura de evidencias en el word.


## Ejecutar la actividad 4

La captura de esta actividad muestra en server3 **un DHCP para VLAN 200 y enrutamiento entre VLAN 100 y VLAN 200**. A diferencia de A3, no se crea DHCP para VLAN 100. Como el escenario no muestra una salida a Internet, este perfil mantiene el bloqueo externo. Se conservan los dos contenedores de server1 y las dos VMs de server2 como clientes de prueba.

| Cliente | Ubicación | Dirección | Asignación |
|---|---|---|---|
| `a4-cont100` | server1 | 192.168.0.11/24 | Estática |
| `a4-vm100` | server2 | 192.168.0.12/24 | Estática |
| `a4-cont200` | server1 | 192.168.2.11/24 | DHCP |
| `a4-vm200` | server2 | 192.168.2.12/24 | DHCP |

Desde server4, en la raíz del proyecto:

```bash
bash DEV/actividad_4/actividad4.sh plan
```

Si el plan termina correctamente:

```bash
bash DEV/actividad_4/actividad4.sh deploy
echo "Codigo de salida actividad 4: $?"
```

El script limpia la topología anterior; crea VLAN 100 sin DHCP y VLAN 200 con DHCP; configura las direcciones de los clientes; ejecuta el script previo `routing_networks.sh 100 200`; e instala una política que permite el tráfico entre ambas subredes y bloquea la salida de los clientes por `ens3`. La conexión de gestión SSH sigue usando `ens3`.

El tránsito entre VLANs se realiza mediante los gateways `192.168.0.1` y `192.168.2.1` y el kernel de server3. Las VLAN siguen separadas en capa 2; se habilita comunicación entre sus redes IPv4 mediante enrutamiento.

Cada cliente debe alcanzar a su gateway, al otro cliente de la misma VLAN y a **los dos clientes de la VLAN opuesta**. Esto cubre contenedor↔contenedor, VM↔VM y contenedor↔VM en ambos sentidos. La verificación también exige que Internet permanezca bloqueado para los clientes, que VLAN 100 no obtenga ofertas DHCP y que VLAN 200 tenga ambas concesiones.

Después de estas pruebas se consultan los contadores del firewall de server3 y se exigen paquetes aceptados en las dos direcciones: `vlan100 → vlan200` y `vlan200 → vlan100`.

```bash
bash DEV/actividad_4/actividad4.sh verify
echo "Codigo de salida verificacion: $?"
```

Deben aparecer `DHCP_LAYOUT_OK VLAN 100: no`, `DHCP_LAYOUT_OK VLAN 200: si`, `ENRUTAMIENTO_INTERVLAN_OK`, `INTERNET_BLOQUEADO_OK`, `ENRUTAMIENTO_BIDIRECCIONAL_CON_CONTADORES_OK` y, al terminar todo, `PASS`. El registro `server3-routing_evidence.log` contiene las reglas y los contadores posteriores a los pings.

Captura de evidencias en el word sobre:  el comando iniciado en server4, una prueba de cada sentido entre VLANs, las asignaciones estáticas/DHCP, los contadores en server3 y el resultado final. Los registros de ambos contenedores y ambas VMs contienen la matriz de pruebas completa.

## Limpieza y cambio de actividad

Cada `deploy` sigue este orden: comprobación de los cuatro destinos → preparación de imágenes → limpieza de server1, server2 y server3 → despliegue en server3, server2 y server1 → espera de los clientes → verificación.

Reconoce los recursos del Lab3, de la primera entrega de A1 y de las cuatro actividades actuales por sus nombres y enlaces a bridges. Incluye bridges OVS/Linux conocidos, TAP, veth, procesos QEMU asociados, contenedores identificados, namespaces DHCP y reglas de firewall del laboratorio.

Antes de limpiar exige que `ens3` conserve la IP y ruta de gestión esperadas. No limpia OFS ni utiliza `pkill` general ni vacía todo iptables. Si encuentra un recurso ambiguo que impide validar la operación, aborta y muestra el motivo.

Conserva inventarios, firewall anterior y discos gestionados en `/var/lib/tel141-a1-backups/ID_DE_EJECUCION/` de cada servidor. El nombre del directorio se mantiene por compatibilidad con la primera entrega. Conserva la base QCOW2 y deja los discos antiguos externos en su ubicación. Los sistemas de archivos de los contenedores retirados no se respaldan; sus volúmenes no se eliminan. No existe restauración automática del escenario anterior.

Para retirar el escenario sin recrearlo:

```bash
bash DEV/actividad_3/actividad3.sh clean
```

Para volver a la actividad 1 utiliza el punto de entrada de **este paquete**:

```bash
bash DEV/actividad_1/actividad1.sh deploy
```


## Evidencias y entrega adicionales

Los registros quedan separados en `DEV/actividad_N/evidencias/FECHA-PID/`, donde N es 1, 2, 3 o 4. La limpieza remota no borra estos registros de server4.

| Evidencia | Archivo principal |
|---|---|
| Ejecución desde server4, orden y resultado | `orquestacion.log`, `resultado.txt` |
| Recursos antes de limpiar | `serverN-check.log` |
| Limpieza y creación | `serverN-clean.log`, `serverN-deploy.log` |
| Configuración estática de las VMs de A2 y de VLAN 100 en A4 | `server2-ready.log` |
| IP y conectividad de ambos contenedores | `server1-verify.log` |
| IP y conectividad dentro de ambas VMs | `server2-verify.log` |
| DHCP/ausencia de DHCP, NAT y firewall | `server3-verify.log` |
| Switch de tránsito | `ofs-verify.log` |
| Paquetes encaminados entre VLANs en A4 | `server3-routing_evidence.log` |


Para la conexión VNC, se abre el túnel hacia server2:

```bash
ssh -p 5802 -N -L 30011:127.0.0.1:5901 -L 30012:127.0.0.1:5902 ubuntu@10.20.11.46
```

Estas evidencias son adicionales, en el word se prioriza la evidencia en mencionada en cada actividad.


