# TEL141 — Lab4, reporte final: actividad 1

Paquete para desplegar **redes aisladas con DHCP y salida a Internet**. La ejecución se inicia desde **server4**, como `ubuntu`. El script principal usa SSH para administrar los demás nodos y reutiliza los scripts del informe previo incluidos en `scripts_IP/`.

Solo se automatiza la actividad 1. Las dos VLAN tienen Internet y deben permanecer aisladas entre sí. Aunque el dibujo incluye la etiqueta genérica de enrutamiento, habilitar comunicación entre las VLAN corresponde a la actividad 4.

## 1. Topología que crea

| Nodo | IP de gestión | Función |
|---|---|---|
| server4 | 10.0.10.4 | Orquestador; aquí se ejecuta el script principal |
| server1 | 10.0.10.1 | OVS `br-int`, dos contenedores y sus enlaces veth |
| server2 | 10.0.10.2 | OVS `br-int`, dos VMs CirrOS y sus interfaces TAP |
| server3 | 10.0.10.3 | OVS `br-int`, gateways, dos servidores DHCP en namespaces y NAT |
| ofs | 10.0.10.5 | Switch de tránsito existente; comprobación de solo lectura |

En server1–3, `ens3` es gestión/salida y `ens4` es el enlace de datos hacia OFS. Los enlaces de datos transportan ambas VLAN; cada puerto de contenedor o VM es un puerto de acceso de su VLAN.

| VLAN | Red | Gateway en server3 | DHCP en namespace | Contenedor en server1 | VM en server2 |
|---|---|---|---|---|---|
| 100 | 192.168.0.0/24 | 192.168.0.1 | 192.168.0.2 | 192.168.0.11 | 192.168.0.12 |
| 200 | 192.168.2.0/24 | 192.168.2.1 | 192.168.2.2 | 192.168.2.11 | 192.168.2.12 |

Las direcciones `.11` y `.12` son **reservas entregadas por DHCP**, no direcciones configuradas estáticamente en los clientes. Los rangos son `.11`–`.15` en cada subred. Esto permite comprobar automáticamente los mismos destinos en cada ejecución.

Se crean `a1-cont100`, `a1-cont200`, `a1-vm100` y `a1-vm200`. Las VMs usan CirrOS 0.5.1, 512 MiB y un vCPU por VM. Los contenedores usan `alpine:3.22`; el registro conserva el identificador de la imagen usada.

## 2. Archivos en el repositorio


| Archivo o carpeta | Para qué sirve |
|---|---|
| `DEV/actividad_1/actividad1.sh` | Principal Bash: revisa, prepara imágenes, limpia, despliega y verifica |
| `DEV/actividad_1/config.sh` | IPs de gestión, clave SSH, imagen y destinos de prueba |
| `DEV/actividad_1/configurar_ssh.sh` | Habilita SSH por clave desde server4 hacia los cuatro destinos |
| `DEV/actividad_1/node.sh` | Operaciones remotas invocadas por el principal |
| `DEV/actividad_1/helpers/` | Limpieza selectiva, contenedores, DHCP, aislamiento y consola serie |
| `DEV/actividad_1/tests/` | Pruebas locales con SSH y consola simulados |
| `DEV/actividad_1/evidencias/` | Se llena automáticamente al ejecutar el despliegue |
| `scripts_IP/` | Funciones reutilizadas del informe previo |

 Aquí `create_vm.sh` incorpora MAC configurable y consola serie; `create_network_vlan.sh` admite reservas DHCP; ambos evitan que sus demonios retengan los bloqueos de ejecución. `delete_vm.sh` conserva la base cuando existen discos archivados que pueden depender de ella. Los demás scripts previos se incluyen como dependencias; la actividad 1 no llama a `routing_networks.sh`.


## 3. Llevar el paquete a server4


Ejecutar:

```powershell
scp -P 5804 .\TEL141_L4_20211602_RF_A1.zip ubuntu@10.20.11.46:~/
ssh -p 5804 ubuntu@10.20.11.46
```


```bash
hostname
sudo apt-get update
sudo apt-get install -y unzip openssh-client
unzip TEL141_L4_20211602_RF_A1.zip
cd ~/TEL141_L4_20211602_RF_A1
```


**Puertos:**  Desde server4 se usa **22** hacia las IP internas; no se usan 5801, 5802 ni 5803 en `config.sh`.

## 4. Configurar SSH una sola vez desde server4

Ejecutar como `ubuntu`, sin anteponer `sudo`:

```bash
bash DEV/actividad_1/configurar_ssh.sh
```

El script crea `~/.ssh/id_ed25519_tel141_s4` sin frase de paso para esta automatización e instala únicamente su parte pública en server1, server2, server3 y OFS. La clave privada permanece en server4 y no debe añadirse al repositorio.

En el primer acceso, comprueba la huella del servidor y responde `yes` si corresponde a tu nodo. `ssh-copy-id` puede pedir la contraseña de cada cuenta `ubuntu`; usa la asignada por el laboratorio. Si no fue cambiada, la guía indica `ubuntu`.

La configuración comprueba además `sudo -n true`. La automatización requiere que la cuenta del laboratorio pueda usar sudo sin una pregunta interactiva. Si aparece `a password is required`, la preparación no terminó: pide al responsable del laboratorio que confirme el acceso administrativo previsto; no cambies sudoers a ciegas.

La configuración anterior de server1 hacia server2 no reemplaza este paso: ahora el origen es server4.

## 5. Instalar dependencias y revisar el plan

Desde la raíz del proyecto, en server4:

```bash
bash DEV/actividad_1/actividad1.sh deps
bash DEV/actividad_1/actividad1.sh plan
```

`deps` instala los paquetes necesarios en server1–3, habilita OVS y Docker donde corresponde. OFS debe traer su OVS operativo; el script no lo reconfigura.

`plan` inspecciona los cuatro destinos y guarda el inventario de los recursos que se retirarían. No elimina ni despliega topología. También comprueba que la gestión y la ruta a server4 usan `ens3`, que KVM está disponible en server2 y que OFS permite ambas VLAN.

Lee los errores si los hay. Si aparece `PLAN_OK` en `resultado.txt`, continúa. Si encuentra un bridge desconocido ocupando `ens4`, una interfaz de gestión mezclada con datos, un proceso inesperado o VNC ocupado por otro servicio, se detiene para que puedas revisar ese caso concreto.

## 6. Limpiar y desplegar la actividad 1

```bash
bash DEV/actividad_1/actividad1.sh deploy
echo "Codigo de salida: $?"
```

**Este comando detiene y retira la topología residual identificada en server1, server2 y server3 antes de crear la nueva.** Ejecuta estas etapas:

1. Verifica por SSH la identidad y los requisitos de los cuatro destinos. Si alguno falla, no inicia la limpieza.
2. Comprueba o descarga Alpine en server1 y la imagen CirrOS en server2. Un fallo en esta etapa también evita la limpieza.
3. Limpia server1, server2 y server3. Conserva inventarios, reglas anteriores y discos gestionados en cada nodo.
4. Configura server3: OVS, VLAN 100/200, gateways, DHCP, forwarding, NAT y reglas de aislamiento.
5. Configura server2 y crea las dos VMs usando `create_vm.sh`.
6. Configura server1 y crea los dos contenedores con cliente DHCP.
7. Espera las concesiones DHCP y verifica los cuatro clientes, server3 y OFS.

Deja abierta la terminal hasta que finalice. Las descargas y el arranque de CirrOS pueden tardar varios minutos. Solo imprime `PASS` si pasan todas las verificaciones; el comando debe devolver código `0`.

Si falla después de comenzar la limpieza, queda registrado `FAILED` y puede haber un despliegue parcial. Conserva los registros, corrige la causa y vuelve a ejecutar `deploy`: esa nueva ejecución vuelve a inventariar y limpiar los recursos reconocidos antes de recrearlos. No hay restauración automática de la topología anterior.

Para repetir únicamente las verificaciones sin recrear recursos:

```bash
bash DEV/actividad_1/actividad1.sh verify
echo "Codigo de salida: $?"
```

Para retirar la topología de laboratorio sin desplegar otra, cuando lo necesites:

```bash
bash DEV/actividad_1/actividad1.sh clean
```

## 7. Alcance de la limpieza

La selección se basa en los nombres usados en el laboratorio y en las conexiones actuales a sus bridges. Incluye los bridges reconocidos `br-int`, `ovs1`, `ovs-br1`, `ovs-br2`, `br1`, `br-lab1` y `br-lab2`; sus enlaces virtuales; namespaces DHCP conocidos; contenedores del laboratorio y procesos QEMU asociados por nombre, disco o TAP.

Se comprueba la identidad actual del proceso antes de detenerlo: no se reutilizan PIDs históricos ni se ejecuta `pkill` general. La limpieza elimina reglas anteriores específicas del laboratorio y las cadenas propias de esta actividad; no vacía globalmente iptables ni elimina reglas de acceso SSH. `ens4`, verificada como interfaz de datos, queda sin direcciones IPv4 anteriores antes de reconstruir el OVS.

Los discos antiguos externos al proyecto se dejan en su ubicación. Los discos y registros gestionados bajo `/var/lib/tel141-l4/` se trasladan a `/var/lib/tel141-a1-backups/ID_DE_EJECUCION/`, junto con el inventario y una copia del firewall. La imagen base se conserva. Estos archivos permiten inspección y recuperación manual, pero no constituyen un restaurador automático. Los sistemas de archivos de los contenedores retirados no se respaldan; sus volúmenes no se borran.

Los recursos desconocidos no se borran indiscriminadamente. Si impiden comprobar una limpieza segura o el despliegue, el script falla y muestra el motivo. El inventario real del laboratorio determinará si hay algún nombre residual adicional que deba incorporarse.

## 8. Evidencias para el reporte y el repositorio

Cada ejecución crea `DEV/actividad_1/evidencias/FECHA-PID/` con:

- `orquestacion.log`: secuencia completa desde server4.
- `serverN-check.log`: inventario anterior y comprobaciones.
- `serverN-clean.log` y `serverN-deploy.log`: limpieza y creación.
- `server1-verify.log`: IP, ruta y pruebas de los dos contenedores.
- `server2-verify.log`: pruebas dentro de ambas VMs mediante consola serie.
- `server3-verify.log`: concesiones DHCP, gateways, NAT y contadores del firewall.
- `ofs-verify.log`: puertos y VLAN del switch de tránsito.
- `config_utilizada.sh` y `resultado.txt`: configuración y resultado de esa ejecución.

En cada cliente se verifica: dirección esperada, ruta por defecto, ping al gateway, ping al equipo de la misma VLAN en el otro servidor, ping a Internet (`8.8.8.8`), resolución DNS (`example.com`) y fallo del ping hacia un equipo de la VLAN opuesta. Las pruebas positivas se exigen antes de aceptar la prueba negativa de aislamiento.

Se adjunta capturas reales del comando iniciado en server4, la finalización con `PASS` y código `0`, y las salidas de DHCP/conectividad/aislamiento. La carpeta `tests/` contiene pruebas simuladas de desarrollo y **no demuestra que tu topología esté funcionando**.

Para subir los archivos al repositorio, una vez integrados y ejecutados allí:

```bash
git status --short
git add scripts_IP DEV/actividad_1
git diff --cached --stat
git commit -m "Automatiza actividad 1 del reporte final de Lab4"
git push
```


## 9. Ver las VMs por VNC


```bash
ssh -p 5802 -N -L 30011:127.0.0.1:5901 -L 30012:127.0.0.1:5902 ubuntu@10.20.11.46
```


