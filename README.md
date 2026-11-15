# Emergencias

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `emergencias` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:emergencias, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/emergencias>.

<!-- Integrante 2 -->

## Integrante 2 · Zonas, inventario y necesidades

Desde PowerShell, en la carpeta del proyecto, inicia la consola y conéctate con un usuario coordinador.

```powershell
mix.bat run -e "Emergencias.iniciar()"
```

```text
connect demo_integrante2 1234 coordinador zona_demo
```

Los ejemplos parten de los datos de `datos_iniciales/`, que el programa copia al arrancar cuando `data/` está vacía. Si ya tienes datos de trabajo, usa una carpeta `data/` vacía para este recorrido y guarda primero tu carpeta actual. Los corchetes indican argumentos opcionales. Escribe entre comillas los nombres y descripciones que contienen espacios.

### Zonas

| Comando | Qué hace |
| --- | --- |
| `register_zone codigo nombre nivel [personas_afectadas]` | Registra una zona raíz. |
| `register_sector codigo_zona codigo_sector nombre [nivel] [personas_afectadas]` | Agrega un sector a una zona. |
| `register_point codigo_sector codigo_punto nombre [nivel] [personas_afectadas]` | Agrega un punto de atención a un sector. |
| `zone_status codigo` | Muestra el nivel, los hijos directos, las estadísticas, los recursos y las necesidades pendientes del árbol consultado. |
| `zone_stats codigo` | Suma las personas afectadas y cuenta los sectores y puntos del árbol consultado. |

La cantidad de personas empieza en cero si se omite. Los sectores y puntos heredan el nivel de su padre cuando no se indica uno.

```text
zone_status zona_demo
zone_stats zona_demo
zone_status demo_sur
register_zone zona_nueva "Zona de práctica" alto 10
register_sector zona_nueva sector_nuevo "Sector de práctica" medio 5
register_point sector_nuevo punto_nuevo "Puesto de práctica" bajo 2
zone_stats zona_nueva
```

`zona_demo` tiene 155 personas afectadas, dos sectores y un punto. `demo_sur` incluye los datos de su punto `demo_p01`. La zona nueva suma 17 personas afectadas.

### Inventario

| Comando | Qué hace |
| --- | --- |
| `register_resource codigo nombre [categoria] cantidad unidad ubicacion` | Crea un recurso. Si se omite la categoría, usa el nombre. |
| `resource_entry codigo cantidad [ubicacion]` | Suma unidades al inventario. |
| `resource_exit codigo cantidad [ubicacion]` | Descuenta unidades si el saldo alcanza. |
| `list_resources [campo=valor ...]` | Lista recursos. Admite filtros por `nombre`, `categoria` o `tipo`, `ubicacion` y `zona`. |
| `transfer_resource codigo origen destino cantidad` | Mueve unidades entre ubicaciones y conserva el código del recurso. |
| `resource_history codigo` | Muestra el historial del recurso, con los movimientos más recientes primero. |
| `critical_resources [umbral]` | Lista existencias por debajo del umbral, que por defecto es 10. |

Si un recurso está en varias ubicaciones, indica la ubicación al registrar una entrada o salida.

```text
list_resources zona=zona_demo
resource_history R001
critical_resources
transfer_resource R002 demo_norte demo_sur 10
resource_entry R002 5 demo_sur
resource_exit R002 2 demo_sur
list_resources categoria=alimentos
register_resource R004 vendas primeros_auxilios 12 unidades demo_p01
```

El historial inicial de `R001` muestra una entrada de 60 litros y una salida de 10. Los botiquines `R003` aparecen entre los recursos críticos porque hay 8 unidades. Después de la transferencia, la entrada y la salida del arroz `R002`, quedan 30 kg en `demo_norte` y 13 kg en `demo_sur`.

### Necesidades

| Comando | Qué hace |
| --- | --- |
| `register_need tipo cantidad prioridad zona descripcion [albergue]` | Crea una solicitud pendiente y devuelve su ID. La zona, sector o punto debe existir. |
| `list_needs [campo=valor ...]` | Lista solicitudes por prioridad. Admite filtros por `zona`, `tipo`, `prioridad`, `estado` y `albergue`. |
| `pending_needs` | Muestra solo las solicitudes pendientes, de mayor a menor prioridad. |
| `assign_resource id recurso cantidad [ubicacion]` | Asigna existencias a la solicitud. Acepta el código del recurso o su nombre dentro de la zona de la solicitud. |
| `update_need id estado` | Cambia el estado a `en_atencion`, `atendida` o `cancelada` cuando la transición es válida. |

Para asignar un recurso cuyo código existe en varios depósitos, indica al final el código de la ubicación. Se permite una asignación confirmada por necesidad, de hasta la cantidad solicitada.

```text
pending_needs
assign_resource N001 R001 30
assign_resource N002 R001 25
update_need N001 en_atencion
update_need N001 atendida
list_needs zona=demo_p01 estado=atendida
zone_status zona_demo
register_need alimentos 5 media demo_norte "Arroz para el turno de la tarde"
pending_needs
exit
```

Con 50 litros disponibles, `N001` recibe 30. El programa rechaza la asignación de 25 litros a `N002` y la deja pendiente. `zone_status zona_demo` muestra el saldo de 20 litros. Si repites el recorrido, usa códigos nuevos al registrar una zona o un recurso, y para las necesidades que crees usa el ID devuelto por el programa.

### Cómo se evita el doble descuento

1. `NecesidadServer` reserva la solicitud antes de pedir el descuento. Si vuelve a llegar una asignación para la misma necesidad y la primera ya se confirmó, la segunda se rechaza.
2. `InventarioServer` comprueba y descuenta el saldo dentro de una sola llamada al `GenServer`. Si dos necesidades compiten por las mismas unidades, cada operación lee el saldo que dejó la anterior.
3. Si el descuento se confirma, la necesidad guarda el código, la ubicación y la cantidad asignada. Si falta inventario, vuelve a `pendiente`. Si el sistema se reinicia entre el descuento y la confirmación, el servidor consulta el historial de inventario para recuperar la asignación sin descontar de nuevo.

La prueba automatizada inicia diez solicitudes que piden 10 litros cada una sobre un saldo de 50. Verifica que cinco se asignen, cinco queden pendientes y el saldo llegue a cero. También prueba dos intentos simultáneos sobre la misma necesidad y transferencias concurrentes que conservan el total.

```powershell
mix.bat test test/concurrencia_test.exs
```

<!-- Fin integrante 2 -->

