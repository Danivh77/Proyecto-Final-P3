# Emergencias

Sistema de consola en Elixir para coordinar la atención después de un terremoto.

## Instalación y ejecución

Instala Elixir 1.20 con Erlang/OTP. El proyecto no tiene dependencias externas.
Abre PowerShell en la carpeta del repositorio.

### Abrir la consola del sistema

```powershell
mix iniciar
```

Usa esta opción para demostrar los comandos del sistema. Al escribir `exit`,
vuelves a PowerShell.

### Abrir IEx para inspeccionar la supervisión

```powershell
iex.bat -S mix
```

En IEx, puedes ver el árbol de supervisión y luego abrir la consola del sistema.

```elixir
Supervisor.which_children(Emergencias.Supervisor)
Emergencias.iniciar()
```

Al escribir `exit` en la consola del sistema, vuelves a IEx. Allí puedes contar
los procesos de albergues con este comando.

```elixir
DynamicSupervisor.count_children(Emergencias.Servidores.AlbergueSupervisor)
```

## Comandos básicos

Prueba estos comandos con los datos de ejemplo.

```text
connect demo_readme clave_demo coordinador demo_norte
zone_status demo_norte
list_needs zona=demo_norte
list_resources zona=demo_norte
check_shelter A01
list_family_messages 1001234567
match_pets
```

Usa `help` para ver los demás comandos.

## Roles y permisos

Cada rol hereda los permisos del anterior.

- **Ciudadano** puede hacer consultas, registrar reportes y enviar mensajes.
- **Voluntario** puede registrar movimientos de inventario, gestionar ingresos y salidas de albergues y buscar coincidencias de mascotas.
- **Coordinador** puede registrar zonas y albergues, asignar y transferir recursos y confirmar coincidencias.
- **Administrador** puede consultar el registro de actividad.

## Estructura

- `lib/` contiene la consola, el dominio, los servidores y la persistencia.
- `test/` contiene las pruebas.
- `datos_iniciales/` contiene los datos de ejemplo.
- `data/` guarda los datos de trabajo y se inicializa con los datos de ejemplo.

## Concurrencia y coincidencias

El servidor de inventario verifica y descuenta el saldo en una sola operación.
Con 50 litros y dos solicitudes simultáneas de 30 y 25 litros, solo una puede
confirmarse. Si falta saldo, la solicitud se rechaza y su reserva se revierte.

Para comparar una mascota perdida y una encontrada, la especie debe coincidir.
Se suman 30 puntos si coincide la zona, 25 por el color, 20 por el tamaño y 5 por
cada palabra en común en las características, hasta 25 puntos por ese último
criterio. Se requieren al menos 60 puntos para sugerir una coincidencia.

## Pruebas

Desde la terminal, ejecuta `mix test`.
