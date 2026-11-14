defmodule Emergencias.CLI.Formatter do
  @moduledoc """
  Convierte los resultados `{:ok, valor}` y `{:error, motivo}` en texto para la consola.
  """

  @doc "Texto a mostrar para un resultado."
  def formatear({:ok, texto}) when is_binary(texto), do: texto
  def formatear({:ok, lista}) when is_list(lista), do: tabla(lista)
  def formatear({:ok, mapa}) when is_map(mapa), do: detalle(mapa)
  def formatear({:ok, valor}), do: valor_texto(valor)
  def formatear(:ok), do: "Listo."
  def formatear({:error, motivo}), do: "Error: " <> mensaje_error(motivo)
  def formatear(otro), do: inspect(otro)

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

  @doc "Mensaje en español para cada motivo de error."
  def mensaje_error(:no_conectado), do: "primero debes conectarte (connect usuario contraseña)."
  def mensaje_error(:sin_permiso), do: "tu tipo de usuario no puede hacer esta acción."
  def mensaje_error(:comando_vacio), do: "escribe un comando. Usa help para ver la lista."
  def mensaje_error(:comillas_sin_cerrar), do: "hay comillas sin cerrar."
  def mensaje_error(:no_implementado), do: "este comando todavía no está implementado."
  def mensaje_error(:no_encontrado), do: "no se encontró el registro."
  def mensaje_error(:id_duplicado), do: "ya existe un registro con ese identificador."
  def mensaje_error(:transicion_invalida), do: "ese cambio de estado no está permitido."
  def mensaje_error(:inventario_insuficiente), do: "no hay suficiente inventario."
  def mensaje_error(:capacidad_llena), do: "el albergue no tiene cupos disponibles."
  def mensaje_error(:ya_resuelto), do: "el reporte ya fue resuelto."
  def mensaje_error(:contrasena_incorrecta), do: "contraseña incorrecta."
  def mensaje_error(:tipo_invalido), do: "tipo de usuario inválido (ciudadano, voluntario, coordinador o administrador)."
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
