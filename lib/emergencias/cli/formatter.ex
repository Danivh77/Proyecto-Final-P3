defmodule Emergencias.CLI.Formatter do
  @moduledoc """
  Convierte los resultados `{:ok, valor}` y `{:error, motivo}` en texto para la consola.
  """

  @doc "Texto a mostrar para un resultado."
  def formatear({:ok, {:resumen, datos}}), do: formatear_resumen(datos)
  def formatear({:ok, lista}) when is_list(lista), do: tabla(lista)
  def formatear({:ok, mapa}) when is_map(mapa), do: detalle(mapa)
  def formatear({:ok, valor}), do: valor_texto(valor)
  def formatear(:ok), do: "Listo."
  def formatear({:error, motivo}), do: "Error: " <> mensaje_error(motivo)
  def formatear(otro), do: inspect(otro)

  @doc "Texto del comando summary a partir de los resúmenes de todos los servidores."
  def formatear_resumen(d) do
    [
      "RESUMEN GLOBAL DEL SISTEMA",
      seccion(d, :usuarios_registrados, "Usuarios", fn ->
        "#{d.usuarios_registrados} registrados, #{d.usuarios_conectados} conectados" <>
          sesiones(d[:sesiones_activas])
      end),
      seccion(d, :zonas, "Zonas", fn ->
        "#{d.zonas} zonas, #{d.sectores} sectores, #{d.puntos} puntos de atención, " <>
          "#{d.personas_afectadas} personas afectadas"
      end),
      seccion(d, :necesidades, "Necesidades", fn ->
        "#{d.necesidades} en total (pendientes #{d.necesidades_pendientes}, " <>
          "asignadas #{d.necesidades_asignadas}, en atención #{d.necesidades_en_atencion}, " <>
          "atendidas #{d.necesidades_atendidas}, canceladas #{d.necesidades_canceladas})"
      end),
      seccion(d, :recursos, "Recursos", fn ->
        "#{d.recursos} registrados, #{d.recursos_criticos} en nivel crítico"
      end),
      seccion(d, :albergues_registrados, "Albergues", fn ->
        "#{d.albergues_registrados} registrados, ocupación " <>
          "#{d.albergues_ocupacion_total}/#{d.albergues_capacidad_total}, " <>
          "#{d.albergues_cupos_libres} cupos libres"
      end),
      seccion(d, :personas_registradas, "Personas", fn ->
        "#{d.personas_registradas} registradas" <> personas_por_estado(d)
      end),
      seccion(d, :mensajes_total, "Mensajes", fn ->
        "#{d.mensajes_total} en total (#{d.mensajes_pendientes} pendientes, " <>
          "#{d.mensajes_entregados} entregados)"
      end),
      seccion(d, :mascotas_reportadas, "Mascotas", fn ->
        "#{d.mascotas_reportadas} reportes (perdidas abiertas #{d.mascotas_perdidas_abiertas}, " <>
          "encontradas abiertas #{d.mascotas_encontradas_abiertas}, " <>
          "posibles coincidencias #{d.mascotas_posibles_coincidencias}, " <>
          "resueltas #{d.mascotas_resueltas})"
      end)
    ]
    |> Enum.join("\n")
  end

  defp seccion(datos, clave, titulo, texto) do
    if Map.has_key?(datos, clave), do: "#{titulo}: #{texto.()}", else: "#{titulo}: no disponible"
  end

  defp sesiones([_ | _] = usuarios), do: " (#{Enum.join(usuarios, ", ")})"
  defp sesiones(_), do: ""

  defp personas_por_estado(datos) do
    estados =
      for {clave, cantidad} <- datos,
          nombre = to_string(clave),
          String.starts_with?(nombre, "personas_"),
          clave not in [:personas_registradas, :personas_afectadas],
          cantidad > 0 do
        "#{String.replace_prefix(nombre, "personas_", "")} #{cantidad}"
      end

    if estados == [], do: "", else: " (" <> Enum.join(Enum.sort(estados), ", ") <> ")"
  end

  @doc "Muestra una lista de mapas o structs como tabla."
  def tabla([]), do: "(sin resultados)"

  def tabla(elementos) when is_list(elementos) do
    if Enum.all?(elementos, &is_map/1) do
      filas = Enum.map(elementos, &a_mapa/1)
      columnas = filas |> hd() |> Map.keys()
      celdas = Enum.map(filas, fn fila -> Enum.map(columnas, &valor_texto(Map.get(fila, &1))) end)
      encabezado = Enum.map(columnas, &to_string/1)
      anchos = anchos_columnas([encabezado | celdas])

      [encabezado, Enum.map(anchos, &String.duplicate("-", &1)) | celdas]
      |> Enum.map_join("\n", &fila_texto(&1, anchos))
    else
      Enum.map_join(elementos, "\n", &valor_texto/1)
    end
  end

  @doc "Muestra un mapa o struct como líneas `campo: valor`."
  def detalle(mapa) when is_map(mapa) do
    mapa
    |> a_mapa()
    |> Enum.map_join("\n", fn {clave, valor} -> "#{clave}: #{valor_texto(valor)}" end)
  end

  @doc "Muestra el estado de una zona con tablas de inventario y solicitudes pendientes."
  def estado_zona(estado) do
    {recursos, estado} = Map.pop!(estado, :recursos)
    {pendientes, datos} = Map.pop!(estado, :necesidades_pendientes)

    solicitudes =
      Enum.map(
        pendientes,
        &Map.take(&1, [:id, :tipo, :cantidad, :prioridad, :zona, :descripcion])
      )

    Enum.join(
      [
        detalle(datos),
        "Recursos\n" <> tabla(recursos),
        "Necesidades pendientes\n" <> tabla(solicitudes)
      ],
      "\n\n"
    )
  end

  @doc "Mensaje en español para cada motivo de error."
  def mensaje_error(:no_conectado), do: "primero debes conectarte (connect usuario contraseña)."
  def mensaje_error(:sin_permiso), do: "tu tipo de usuario no puede hacer esta acción."
  def mensaje_error(:comando_vacio), do: "escribe un comando. Usa help para ver la lista."
  def mensaje_error(:comillas_sin_cerrar), do: "hay comillas sin cerrar."
  def mensaje_error(:no_implementado), do: "este comando todavía no está implementado."
  def mensaje_error(:no_encontrado), do: "no se encontró el registro."
  def mensaje_error(:id_duplicado), do: "ya existe un registro con ese identificador."
  def mensaje_error(:codigo_invalido), do: "el código no puede estar vacío."
  def mensaje_error(:nombre_invalido), do: "el nombre no puede estar vacío."
  def mensaje_error(:nivel_invalido), do: "el nivel debe ser crítico, alto, medio o bajo."

  def mensaje_error(:personas_afectadas_invalidas),
    do: "la cantidad de personas afectadas debe ser un entero mayor o igual a cero."

  def mensaje_error(:jerarquia_invalida),
    do: "los sectores pertenecen a una zona y los puntos a un sector."

  def mensaje_error(:transicion_invalida), do: "ese cambio de estado no está permitido."
  def mensaje_error(:inventario_insuficiente), do: "no hay suficiente inventario."
  def mensaje_error(:zona_no_encontrada), do: "registra la zona, sector o punto antes de usarlo."
  def mensaje_error(:tipo_necesidad_invalido), do: "el tipo de necesidad no es válido."
  def mensaje_error(:descripcion_invalida), do: "la descripción no puede estar vacía."
  def mensaje_error(:prioridad_invalida), do: "la prioridad debe ser crítica, alta, media o baja."
  def mensaje_error(:responsable_invalido), do: "el responsable no puede estar vacío."
  def mensaje_error(:albergue_invalido), do: "el código de albergue no puede estar vacío."
  def mensaje_error(:ya_asignada), do: "la necesidad ya tiene recursos asignados."
  def mensaje_error(:reserva_activa), do: "hay una reserva activa para esta necesidad."
  def mensaje_error(:asignacion_invalida), do: "la asignación indicada no es válida."

  def mensaje_error(:cantidad_asignacion_invalida),
    do: "asigna una cantidad positiva que no supere la cantidad solicitada."

  def mensaje_error(:ubicacion_requerida), do: "indica la ubicación de este recurso."

  def mensaje_error(:destino_invalido),
    do: "el destino debe ser distinto del origen y no estar vacío."

  def mensaje_error(:cantidad_invalida), do: "cantidad fuera del rango permitido."
  def mensaje_error(:categoria_invalida), do: "la categoría no puede estar vacía."
  def mensaje_error(:unidad_invalida), do: "la unidad no puede estar vacía."
  def mensaje_error(:ubicacion_invalida), do: "la ubicación no puede estar vacía."
  def mensaje_error(:capacidad_llena), do: "el albergue no tiene cupos disponibles."
  def mensaje_error(:albergue_no_encontrado), do: "no existe un albergue con ese código."
  def mensaje_error(:albergue_ya_existe), do: "ya existe un albergue con ese código."
  def mensaje_error(:capacidad_invalida), do: "la capacidad debe ser un número mayor que cero."
  def mensaje_error(:datos_invalidos), do: "faltan datos o hay datos vacíos."
  def mensaje_error(:documento_invalido), do: "el documento no puede estar vacío."
  def mensaje_error(:ya_esta_dentro), do: "esa persona ya está en el albergue."
  def mensaje_error(:no_esta_dentro), do: "esa persona no está en el albergue."
  def mensaje_error(:ya_asociado), do: "ya estaba asociado al albergue."
  def mensaje_error(:limite_invalido), do: "la cantidad debe ser un número mayor que cero."

  def mensaje_error(:persona_no_encontrada),
    do: "no hay una persona registrada con ese documento."

  def mensaje_error(:persona_ya_registrada),
    do: "ya hay una persona registrada con ese documento."

  def mensaje_error(:edad_invalida),
    do: "la edad debe ser un número mayor o igual a cero (o - si no se sabe)."

  def mensaje_error(:estado_invalido), do: "estado no válido."
  def mensaje_error(:mensaje_no_encontrado), do: "no existe un mensaje con ese id."
  def mensaje_error(:remitente_invalido), do: "el remitente no puede estar vacío."

  def mensaje_error(:destinatario_invalido),
    do: "el documento del destinatario no puede estar vacío."

  def mensaje_error(:contenido_invalido), do: "el mensaje no puede estar vacío."
  def mensaje_error(:ya_entregado), do: "el mensaje ya estaba marcado como entregado."
  def mensaje_error(:ya_pendiente), do: "el mensaje ya estaba pendiente."
  def mensaje_error(:tipo_reporte_invalido), do: "el tipo de reporte debe ser lost o found."
  def mensaje_error(:reporte_no_encontrado), do: "no existe un reporte con ese id."
  def mensaje_error(:mismo_reporte), do: "debes indicar dos reportes distintos."
  def mensaje_error(:tipos_incompatibles), do: "se necesita un reporte perdido y uno encontrado."
  def mensaje_error(:especies_distintas), do: "los reportes son de especies distintas."
  def mensaje_error(:filtros_invalidos), do: "filtros inválidos."
  def mensaje_error(:ya_resuelto), do: "el reporte ya fue resuelto."
  def mensaje_error(:contrasena_incorrecta), do: "contraseña incorrecta."

  def mensaje_error(:tipo_invalido),
    do: "tipo de usuario inválido (ciudadano, voluntario, coordinador o administrador)."

  def mensaje_error(:usuario_invalido), do: "el usuario debe tener de 3 a 20 letras, números o _."
  def mensaje_error(:contrasena_invalida), do: "la contraseña debe tener al menos 4 caracteres."
  def mensaje_error(:zona_invalida), do: "la zona no puede estar vacía."
  def mensaje_error(:ya_conectado), do: "ese usuario ya está conectado."
  def mensaje_error(:sesion_activa), do: "ya hay una sesión abierta. Usa disconnect primero."
  def mensaje_error(:logger_no_disponible), do: "el registro de actividad no está disponible."
  def mensaje_error(:tiempo_agotado), do: "el sistema tardó demasiado en responder."
  def mensaje_error({:comando_desconocido, nombre}), do: "comando desconocido: #{nombre}."

  def mensaje_error({:comando_no_implementado, nombre}),
    do: "el comando #{nombre} todavía no está implementado."

  def mensaje_error({:uso, uso}), do: "argumentos incorrectos. Uso: #{uso}"
  def mensaje_error({:numero_invalido, texto}), do: "\"#{texto}\" no es un número válido."

  def mensaje_error({:cantidad_invalida, texto}),
    do: "\"#{texto}\" debe ser un número mayor que cero."

  def mensaje_error({:filtro_invalido, texto}), do: "filtro inválido: #{texto}."
  def mensaje_error(motivo), do: inspect(motivo)

  defp a_mapa(%_{} = struct), do: Map.from_struct(struct)
  defp a_mapa(mapa), do: mapa

  defp valor_texto(nil), do: "-"
  defp valor_texto(texto) when is_binary(texto), do: texto
  defp valor_texto(%NaiveDateTime{} = fecha), do: NaiveDateTime.to_string(fecha)
  defp valor_texto(%MapSet{} = conjunto), do: conjunto |> MapSet.to_list() |> valor_texto()
  defp valor_texto(lista) when is_list(lista), do: Enum.map_join(lista, ", ", &valor_texto/1)
  defp valor_texto(valor) when is_atom(valor) or is_number(valor), do: to_string(valor)
  defp valor_texto(valor), do: inspect(valor)

  defp anchos_columnas(filas) do
    filas
    |> Enum.zip()
    |> Enum.map(fn columna ->
      columna |> Tuple.to_list() |> Enum.map(&String.length/1) |> Enum.max()
    end)
  end

  defp fila_texto(celdas, anchos) do
    celdas
    |> Enum.zip(anchos)
    |> Enum.map_join("  ", fn {celda, ancho} -> String.pad_trailing(celda, ancho) end)
    |> String.trim_trailing()
  end
end
