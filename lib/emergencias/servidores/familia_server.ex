defmodule Emergencias.Servidores.FamiliaServer do
  @moduledoc """
  Guarda las personas afectadas y los mensajes para sus familiares.

  """

  use GenServer

  alias Emergencias.Dominio.{Mensaje, Persona}
  alias Emergencias.Persistencia
  alias Emergencias.Util.{Fechas, Ids}

  @archivo_personas "personas.txt"
  @archivo_mensajes "mensajes.txt"


  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra una persona afectada. `edad` puede ser `nil`; `estado` es `:reportada` por defecto
  (átomo o texto).
  """
  def reportar_persona(documento, nombre, edad, zona, estado \\ :reportada) do
    GenServer.call(__MODULE__, {:reportar_persona, documento, nombre, edad, zona, estado})
  end

  @doc "Busca una persona por documento. Devuelve `{:ok, persona}` o `{:error, :persona_no_encontrada}`."
  def buscar(documento), do: GenServer.call(__MODULE__, {:buscar, documento})

  @doc """
  Busca personas con filtros (`:nombre`, `:documento`, `:zona`, `:estado`; keyword o mapa).
  Devuelve `{:ok, lista}` ordenada por id.
  """
  def buscar_por(filtros \\ []) do
    if is_list(filtros) or is_map(filtros) do
      GenServer.call(__MODULE__, {:buscar_por, filtros})
    else
      {:error, :filtros_invalidos}
    end
  end

  @doc """
  Cambia el estado de una persona validando la transición.

  """
  def cambiar_estado(documento, nuevo_estado, _usuario \\ "sistema") do
    GenServer.call(__MODULE__, {:cambiar_estado, documento, nuevo_estado})
  end

  @doc "Historial de cambios de estado: `{:ok, [%{fecha:, de:, a:}]}`."
  def historial(documento), do: GenServer.call(__MODULE__, {:historial, documento})

  @doc """
  Guarda un mensaje (queda `:pendiente`) dirigido al documento de una persona o familia.
  No exige que la persona esté registrada: un familiar puede dejar el mensaje antes.
  """
  def enviar_mensaje(remitente, documento, contenido) do
    GenServer.call(__MODULE__, {:enviar_mensaje, remitente, documento, contenido})
  end

  @doc "Mensajes dirigidos a un documento: `{:ok, lista}` en orden de envío."
  def listar_mensajes(documento), do: GenServer.call(__MODULE__, {:listar_mensajes, documento})

  @doc "Marca un mensaje como `\"entregado\"` o `\"pendiente\"` (texto o átomo)."
  def marcar_mensaje(id, estado), do: GenServer.call(__MODULE__, {:marcar_mensaje, id, estado})

  @doc "Totales para el comando summary."
  def resumen, do: GenServer.call(__MODULE__, :resumen)


  @impl true
  def init(:ok) do
    {:ok, personas} = Persistencia.cargar(@archivo_personas, &Persona.desde_linea/1)
    {:ok, mensajes} = Persistencia.cargar(@archivo_mensajes, &Mensaje.desde_linea/1)

    {:ok, %{personas: Map.new(personas, fn p -> {p.documento, p} end), mensajes: mensajes}}
  end

  @impl true
  def handle_call({:reportar_persona, documento, nombre, edad, zona, estado}, _from, datos) do
    id = Ids.siguiente("P", ids_de(datos.personas))

    with {:ok, persona} <- Persona.nuevo(id, documento, nombre, edad, zona, estado),
         :ok <- verificar_libre(datos.personas, persona.documento),
         personas = Map.put(datos.personas, persona.documento, persona),
         :ok <- guardar_personas(personas) do
      {:reply, {:ok, persona}, %{datos | personas: personas}}
    else
      error -> {:reply, error, datos}
    end
  end

  def handle_call({:buscar, documento}, _from, datos) do
    {:reply, obtener_persona(datos.personas, documento), datos}
  end

  def handle_call({:buscar_por, filtros}, _from, datos) do
    encontradas =
      datos.personas
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Persona.buscar(filtros)

    {:reply, {:ok, encontradas}, datos}
  end

  def handle_call({:cambiar_estado, documento, nuevo_estado}, _from, datos) do
    with {:ok, persona} <- obtener_persona(datos.personas, documento),
         {:ok, actualizada} <- Persona.transicion(persona, nuevo_estado, ahora()),
         personas = Map.put(datos.personas, actualizada.documento, actualizada),
         :ok <- guardar_personas(personas) do
      {:reply, {:ok, actualizada}, %{datos | personas: personas}}
    else
      error -> {:reply, error, datos}
    end
  end

  def handle_call({:historial, documento}, _from, datos) do
    respuesta =
      with {:ok, persona} <- obtener_persona(datos.personas, documento) do
        {:ok, Enum.map(persona.historial, fn {fecha, de, a} -> %{fecha: fecha, de: de, a: a} end)}
      end

    {:reply, respuesta, datos}
  end

  def handle_call({:enviar_mensaje, remitente, documento, contenido}, _from, datos) do
    id = Ids.siguiente("MSG", Enum.map(datos.mensajes, & &1.id))

    with {:ok, mensaje} <- Mensaje.nuevo(remitente, documento, contenido, id: id, fecha: ahora()),
         mensajes = datos.mensajes ++ [mensaje],
         :ok <- guardar_mensajes(mensajes) do
      {:reply, {:ok, mensaje}, %{datos | mensajes: mensajes}}
    else
      error -> {:reply, error, datos}
    end
  end

  def handle_call({:listar_mensajes, documento}, _from, datos) do
    destinatario = limpiar(documento)
    {:reply, {:ok, Enum.filter(datos.mensajes, &(&1.destinatario == destinatario))}, datos}
  end

  def handle_call({:marcar_mensaje, id, estado}, _from, datos) do
    with {:ok, destino} <- Mensaje.estado_desde_texto(estado),
         {:ok, mensaje} <- buscar_mensaje(datos.mensajes, id),
         {:ok, actualizado} <- aplicar_estado(mensaje, destino),
         mensajes = reemplazar_mensaje(datos.mensajes, actualizado),
         :ok <- guardar_mensajes(mensajes) do
      {:reply, {:ok, actualizado}, %{datos | mensajes: mensajes}}
    else
      error -> {:reply, error, datos}
    end
  end

  def handle_call(:resumen, _from, datos) do
    por_estado = datos.personas |> Map.values() |> Enum.frequencies_by(& &1.estado)

    personas_por_estado =
      Map.new(Persona.estados(), fn estado ->
        {:"personas_#{estado}", Map.get(por_estado, estado, 0)}
      end)

    resumen =
      Map.merge(personas_por_estado, %{
        personas_registradas: map_size(datos.personas),
        mensajes_total: length(datos.mensajes),
        mensajes_pendientes: Enum.count(datos.mensajes, &(&1.estado == :pendiente)),
        mensajes_entregados: Enum.count(datos.mensajes, &(&1.estado == :entregado))
      })

    {:reply, resumen, datos}
  end


  defp ahora, do: Fechas.formatear(Fechas.ahora())

  defp limpiar(valor) when is_binary(valor), do: String.trim(valor)
  defp limpiar(_), do: nil

  defp ids_de(personas), do: personas |> Map.values() |> Enum.map(& &1.id)

  defp verificar_libre(personas, documento) do
    if Map.has_key?(personas, documento), do: {:error, :persona_ya_registrada}, else: :ok
  end

  defp obtener_persona(personas, documento) do
    case Map.fetch(personas, limpiar(documento)) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, :persona_no_encontrada}
    end
  end

  defp buscar_mensaje(mensajes, id) do
    id = id |> limpiar() |> mayusculas()

    case Enum.find(mensajes, &(&1.id == id)) do
      nil -> {:error, :mensaje_no_encontrado}
      mensaje -> {:ok, mensaje}
    end
  end

  defp mayusculas(nil), do: nil
  defp mayusculas(texto), do: String.upcase(texto)

  defp aplicar_estado(mensaje, :entregado), do: Mensaje.marcar_entregado(mensaje)
  defp aplicar_estado(mensaje, :pendiente), do: Mensaje.marcar_pendiente(mensaje)

  defp reemplazar_mensaje(mensajes, actualizado) do
    Enum.map(mensajes, fn m -> if m.id == actualizado.id, do: actualizado, else: m end)
  end

  defp guardar_personas(personas) do
    lista = personas |> Map.values() |> Enum.sort_by(& &1.id)
    Persistencia.guardar(@archivo_personas, lista, &Persona.a_linea/1)
  end

  defp guardar_mensajes(mensajes) do
    Persistencia.guardar(@archivo_mensajes, mensajes, &Mensaje.a_linea/1)
  end
end
