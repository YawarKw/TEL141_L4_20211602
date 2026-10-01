# TEL141 Laboratorio 4

Edgar Diaz Zevillanos / 20211602. 

Implementación en Bash de los nueve scripts de la actividad 2. `scripts/common.sh` es una biblioteca compartida y debe permanecer junto a los nueve scripts. Los scripts se ejecutan en los servidores Linux del laboratorio, con `sudo`.

A continuación una guía para el uso de estos scripts:

## Preparación

En Ubuntu/Debian, en cada servidor que corresponda:

```bash
sudo apt update
sudo apt install -y openvswitch-switch iproute2 iptables dnsmasq-base \
  qemu-system-x86 qemu-utils curl util-linux openssh-client openssh-server
sudo systemctl enable --now openvswitch-switch
sudo systemctl enable --now ssh
cd TEL141_L4_20211602/scripts
chmod +x *.sh
ip -br address
ip -4 route
sudo ovs-vsctl show
sudo iptables -S FORWARD
```

Identifique antes el master, los workers, la interfaz de gestión, la salida a Internet y los enlaces de datos. `ens4` y `ens3` en los ejemplos son nombres ilustrativos y deben coincidir con la topología real. Use interfaces de datos sin direcciones IP globales. `init_master.sh` cambia la política FORWARD a DROP y puede interrumpir tráfico reenviado existente: ejecútelo en el nodo destinado al laboratorio.

Se presupone un entorno de laboratorio sin reglas ajenas que permitan o bloqueen estos flujos, enlaces entre OVS capaces de transportar 802.1Q y ausencia de un controlador OpenFlow que sustituya el switching normal de OVS. Las reglas existentes no se borran. Con UFW, Docker, libvirt u otro gestor, revise previamente sus cadenas: una regla ACCEPT ajena puede mantener un acceso que estos scripts retiren.

## Parámetros

| Script | Argumentos |
|---|---|
| `init_master.sh` | `INTERFAZ_DATOS [OTRA...]` |
| `create_network_vlan.sh` | `VLAN RED/CIDR si INICIO,FIN` o `VLAN RED/CIDR no` |
| `internet_to_network.sh` | `VLAN RED/CIDR` |
| `routing_networks.sh` | `VLAN_1 VLAN_2` |
| `no_internet_to_network.sh` | `VLAN RED/CIDR` |
| `no_routing_networks.sh` | `VLAN_1 VLAN_2` |
| `init_worker.sh` | `INTERFAZ_DATOS [OTRA...]` |
| `create_vm.sh` | `NOMBRE OVS VLAN PUERTO_TCP_VNC` |
| `delete_vm.sh` | `NOMBRE OVS VLAN PUERTO_TCP_VNC` |

VLAN: 1 a 4094. Redes: IPv4, dirección de red canónica y prefijo /1 a /30; con DHCP debe quedar espacio para clientes. La primera IP **utilizable** es el gateway y la segunda es el servidor DHCP. El rango excluye red, broadcast y ambas direcciones reservadas. Se rechazan redes solapadas con las rutas conectadas del host. El modo `no` no inicia DHCP; en una VLAN ya gestionada también retira su DHCP anterior. La red de una VLAN existente no se renumera automáticamente.

## Ejemplo de despliegue

En el **master**, con `ens4` como enlace de datos:

```bash
sudo ./init_master.sh ens4
sudo ./create_network_vlan.sh 100 192.168.0.0/24 no
sudo ./create_network_vlan.sh 200 192.168.2.0/24 si 192.168.2.11,192.168.2.15
sudo ./internet_to_network.sh 100 192.168.0.0/24
sudo ./routing_networks.sh 100 200
```

La salida a Internet se toma de la única interfaz de las rutas por defecto IPv4. Si hay varias, o se requiere seleccionar otra:

```bash
sudo env EXT_IF=ens3 ./internet_to_network.sh 100 192.168.0.0/24
```

En cada **worker**, con su enlace de datos real:

```bash
sudo ./init_worker.sh ens4
sudo ./create_vm.sh vm100 br-int 100 5901
sudo ./create_vm.sh vm200 br-int 200 5902
```

Se requiere `/dev/kvm` accesible. Cada VM usa 512 MiB, una vCPU, NIC e1000, TAP de acceso a su VLAN y un delta QCOW2. La MAC incorpora el identificador del host y el nombre de VM. Se usa CirrOS 0.5.1 para mantener continuidad con el laboratorio 3, sin afirmar que sea la versión más reciente. Si la imagen no existe en el almacén privado, se copia la imagen del directorio de ejecución con el mismo nombre o se descarga por HTTPS desde CirrOS. El archivo se valida con `qemu-img info` antes de utilizarlo.

Los puertos VNC son **puertos TCP completos**: 5901 se transforma en display `:1`. VNC escucha en `127.0.0.1` del worker. Abra un túnel desde la PC (reemplace usuario, IP y puerto SSH):

```bash
ssh -N -L 30011:127.0.0.1:5901 usuario@IP_DEL_WORKER
```

En RealVNC conecte a `127.0.0.1:30011`. El puerto local 30011 es solo un ejemplo libre. Para la segunda VM use otra redirección hacia 5902.

En CirrOS, consulte las credenciales mostradas en su consola de arranque. Para **vm100** sin DHCP, como root y tras identificar la interfaz (`ip link`), por ejemplo `eth0`:

```bash
sudo ip link set eth0 up
sudo ip addr add 192.168.0.10/24 dev eth0
sudo ip route add default via 192.168.0.1
echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf
ping -c 3 192.168.0.1
ping -c 3 8.8.8.8
```

Use una IP libre y distinta en cada VM. Si una dirección o ruta ya existe, consúltela y ajuste en vez de añadir otra. En **vm200**, CirrOS intenta DHCP al arrancar; compruebe `ip -4 addr` e `ip route`. Si necesita solicitar una concesión y no hay otro cliente DHCP activo, utilice `sudo udhcpc -i eth0 -n -q`. Debe recibir una IP del rango 192.168.2.11 a 192.168.2.15 y gateway 192.168.2.1. Tener DNS 8.8.8.8 no concede acceso a Internet a la VLAN 200.

## Verificación y evidencias

En el master:

```bash
sudo ovs-vsctl show
ip -4 addr show vlan100
ip -4 addr show vlan200
sysctl net.ipv4.ip_forward
sudo iptables -S FORWARD
sudo iptables -t nat -S POSTROUTING
sudo ip netns exec ns-dhcp-200 ip -4 addr
sudo ip netns exec ns-dhcp-200 ss -lunp
sudo cat /var/lib/tel141-l4/networks/dnsmasq-200.leases
```

Desde cada VM, pruebe su gateway, la IP real de la VM de la otra VLAN y 8.8.8.8. Repita después de retirar los permisos. Una respuesta del gateway prueba conectividad local; no demuestra por sí sola que exista acceso a Internet o comunicación entre clientes de distintas VLAN.

```bash
# Master
sudo ./no_internet_to_network.sh 100 192.168.0.0/24
sudo ./no_routing_networks.sh 100 200

# Worker: detiene QEMU y elimina TAP, puerto OVS, delta y metadatos.
sudo ./delete_vm.sh vm100 br-int 100 5901
sudo ./delete_vm.sh vm200 br-int 200 5902
```

El borrado de la VM es definitivo. El proceso se verifica por ejecutable y argumento de disco antes de detenerlo. Si no termina, los recursos se conservan. La base privada se elimina solo cuando no queda ningún delta gestionado. No use esa base como backing file de discos externos al proyecto. La imagen original que se copió desde otro directorio no se elimina.

## Estado y límites

- Estado privado: `/var/lib/tel141-l4/`. No lo borre ni modifique manualmente mientras existan recursos gestionados.
- La exclusión con `flock` serializa operaciones. El descriptor se cierra en los demonios.
- Las reglas incluyen comentarios `TEL141-L4-...`; repetir las altas no las duplica. Las bajas retiran las reglas propias de ambos sentidos.
- No se implementa un gestor de arranque. Las IP, namespaces, procesos y reglas de iptables deben recrearse tras reiniciar. La configuración OVS puede persistir, pero ello no restaura las demás capas.
- Si falla `create_vm.sh` después de crear el registro, use `delete_vm.sh` con los mismos argumentos antes de reintentar.
- No se ha ejecutado un despliegue real en los servidores del alumno. Las pruebas incluidas no reemplazan evidencias SSH, pings, DHCP ni arranque de VMs.



## Documentación consultada

Consulta: 28 de septiembre de 2026.

- OpenSSH: https://man.openbsd.org/ssh.1
- OpenSSH configuración: https://man.openbsd.org/ssh_config.5
- OpenSSH claves: https://man.openbsd.org/ssh-keygen.1
- Ubuntu OpenSSH: https://ubuntu.com/server/docs/how-to/security/openssh-server/
- Python subprocess: https://docs.python.org/3/library/subprocess.html
- Ansible: https://docs.ansible.com/projects/ansible/latest/command_guide/intro_adhoc.html
- PSSH: https://github.com/lilydjwg/pssh
- OVS VLAN: https://docs.openvswitch.org/en/latest/faq/vlan/
- Linux ip_forward: https://docs.kernel.org/networking/ip-sysctl.html
- dnsmasq: https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
- Netfilter NAT: https://www.netfilter.org/documentation/HOWTO/NAT-HOWTO-6.html
- QEMU: https://www.qemu.org/docs/master/system/invocation.html
- qemu-img: https://www.qemu.org/docs/master/tools/qemu-img.html
- CirrOS 0.5.1: https://download.cirros-cloud.net/0.5.1/
