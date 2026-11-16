defmodule Emergencias.Dominio.Necesidad do
  @moduledoc """
  Solicitud de ayuda con prioridad, estado e historial de cambios.
  Las operaciones devuelven nuevas estructuras y trabajan en memoria.
  """

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Persistencia

  @tipos ~w(agua alimentos medicamentos primeros_auxilios refugio transporte rescate otra)
  @prioridades %{"critica" => 4, "alta" => 3, "media" => 2, "baja" => 1}
  @estados ~w(pendiente asignada en_atencion atendida cancelada)
  @filtros [:zona, :tipo, :prioridad, :estado, :albergue]

  defstruct [
    :id,
    :tipo,
    :descripcion,
    :cantidad,
    :zona,
    :prioridad,
    :responsable,
    :estado,
    :albergue,
    asignaciones: [],
    historial: []
  ]

  @doc "Crea una necesidad pendiente sin albergue ni asignaciones."
  def nuevo(id, tipo, descripcion, cantidad, zona, prioridad, responsable) do
    cond do
      vacio?(id) ->
        {:error, :id_invalido}

      not tipo_valido?(tipo) ->
        {:error, :tipo_necesidad_invalido}

      vacio?(descripcion) ->
        {:error, :descripcion_invalida}

      not is_integer(cantidad) or cantidad <= 0 ->
        {:error, :cantidad_invalida}

      vacio?(zona) ->
        {:error, :zona_invalida}

      not prioridad_valida?(prioridad) ->
        {:error, :prioridad_invalida}

      vacio?(responsable) ->
        {:error, :responsable_invalido}

      true ->
        {:ok,
         %__MODULE__{
           id: String.trim(id),
           tipo: tipo,
           descripcion: descripcion,
           cantidad: cantidad,
           zona: zona,
           prioridad: prioridad_canonica(prioridad),
           responsable: responsable,
           estado: "pendiente"
         }}
    end
  end

  def tipo_valido?(tipo), do: tipo in @tipos
  def prioridad_valida?(prioridad), do: Map.has_key?(@prioridades, prioridad_canonica(prioridad))

  @doc "Devuelve el peso de la prioridad. Una prioridad desconocida tiene peso cero."
  def valor_prioridad(prioridad), do: Map.get(@prioridades, prioridad_canonica(prioridad), 0)

  @doc "Cambia el estado y registra el par {anterior, nuevo}, del más reciente al más antiguo."
  def transicion(%__MODULE__{estado: "asignada", asignaciones: []} = necesidad, "pendiente"),
    do: cambiar_estado(necesidad, "pendiente")

  def transicion(%__MODULE__{estado: "pendiente"} = necesidad, "asignada"),
    do: cambiar_estado(necesidad, "asignada")

  def transicion(%__MODULE__{estado: "asignada"} = necesidad, "en_atencion"),
    do: cambiar_estado(necesidad, "en_atencion")

  def transicion(%__MODULE__{estado: "en_atencion"} = necesidad, "atendida"),
    do: cambiar_estado(necesidad, "atendida")

  def transicion(%__MODULE__{estado: estado} = necesidad, "cancelada")
      when estado in ["pendiente", "asignada", "en_atencion"],
      do: cambiar_estado(necesidad, "cancelada")

  def transicion(%__MODULE__{}, _estado), do: {:error, :transicion_invalida}

  defp cambiar_estado(necesidad, estado) do
    historial = [{necesidad.estado, estado} | necesidad.historial]
    {:ok, %{necesidad | estado: estado, historial: historial}}
  end

  @doc "Inserta una necesidad en una lista ordenada, después de las de igual prioridad."
  def insertar_por_prioridad(necesidad, []), do: [necesidad]

  def insertar_por_prioridad(necesidad, [primera | resto] = ordenadas) do
    if valor_prioridad(necesidad.prioridad) > valor_prioridad(primera.prioridad) do
      [necesidad | ordenadas]
    else
      [primera | insertar_por_prioridad(necesidad, resto)]
    end
  end

  @doc "Ordena de mayor a menor prioridad y conserva el orden de entrada en los empates."
  def ordenar_por_prioridad(necesidades),
    do: Enum.reduce(necesidades, [], &insertar_por_prioridad/2)

  @doc "Devuelve las necesidades que cumplen todos los filtros indicados."
  def filtrar(necesidades, filtros) do
    Enum.filter(necesidades, fn necesidad ->
      Enum.all?(filtros, fn
        {:prioridad, valor} ->
          necesidad.prioridad == prioridad_canonica(valor)

        {:albergue, valor} when is_binary(valor) and is_binary(necesidad.albergue) ->
          Albergue.normalizar_codigo(necesidad.albergue) ==
            Albergue.normalizar_codigo(valor)

        {campo, valor} when campo in @filtros ->
          Map.fetch!(necesidad, campo) == valor

        _ ->
          false
      end)
    end)
  end

  @doc """
  Guarda la necesidad, incluyendo asignaciones {código, ubicación, cantidad}
  y cambios de estado, en una línea de texto.
  """
  def a_linea(%__MODULE__{} = necesidad) do
    Persistencia.unir_campos([
      necesidad.id,
      necesidad.tipo,
      necesidad.descripcion,
      necesidad.cantidad,
      necesidad.zona,
      necesidad.prioridad,
      necesidad.responsable,
      necesidad.estado,
      necesidad.albergue,
      escribir_registros(necesidad.asignaciones),
      escribir_registros(necesidad.historial)
    ])
  end

  @doc "Recupera una necesidad desde una línea validando sus campos y registros."
  def desde_linea(linea) when is_binary(linea) do
    with [
           id,
           tipo,
           descripcion,
           texto,
           zona,
           prioridad,
           responsable,
           estado,
           albergue,
           asignaciones,
           historial
         ] <- Persistencia.separar_campos(linea),
         {cantidad, ""} <- Integer.parse(texto),
         true <- estado in @estados,
         {:ok, necesidad} <- nuevo(id, tipo, descripcion, cantidad, zona, prioridad, responsable),
         {:ok, asignaciones} <- leer_registros(asignaciones, &leer_asignacion/1),
         {:ok, historial} <- leer_registros(historial, &leer_cambio/1) do
      {:ok,
       %{
         necesidad
         | estado: estado,
           albergue: if(albergue == "", do: nil, else: albergue),
           asignaciones: asignaciones,
           historial: historial
       }}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp escribir_registros(registros) do
    registros
    |> Enum.map(fn registro -> registro |> Tuple.to_list() |> Persistencia.unir_campos() end)
    |> Persistencia.unir_campos()
  end

  defp leer_registros("", _leer), do: {:ok, []}

  defp leer_registros(texto, leer) do
    texto
    |> Persistencia.separar_campos()
    |> Enum.reduce_while({:ok, []}, fn registro, {:ok, acumulado} ->
      case leer.(Persistencia.separar_campos(registro)) do
        {:ok, valor} -> {:cont, {:ok, [valor | acumulado]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, registros} -> {:ok, Enum.reverse(registros)}
      error -> error
    end
  end

  defp leer_asignacion([codigo, ubicacion, texto]) do
    with false <- vacio?(codigo) or vacio?(ubicacion),
         {cantidad, ""} when cantidad > 0 <- Integer.parse(texto) do
      {:ok, {codigo, ubicacion, cantidad}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  defp leer_asignacion(_), do: {:error, :linea_invalida}

  defp leer_cambio([anterior, nuevo]) when anterior in @estados and nuevo in @estados,
    do: {:ok, {anterior, nuevo}}

  defp leer_cambio(_), do: {:error, :linea_invalida}

  defp prioridad_canonica("crítica"), do: "critica"
  defp prioridad_canonica(prioridad), do: prioridad

  defp vacio?(texto) when is_binary(texto), do: String.trim(texto) == ""
  defp vacio?(_), do: true
end
