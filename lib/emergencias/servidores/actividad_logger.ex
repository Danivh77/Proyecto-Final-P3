defmodule Emergencias.Servidores.ActividadLogger do
  @moduledoc """
  Registra la actividad de los usuarios.
  Es un proceso hecho con `spawn_link` y `receive`, sin GenServer.
  Cada entrada es una tupla `{fecha, usuario, accion}` y se guarda en `actividad.log`.
  """

  alias Emergencias.Persistencia
  alias Emergencias.Util.Fechas

  @nombre __MODULE__
  @archivo "actividad.log"
  @tiempo_espera 5_000

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Inicia el proceso y lo registra con el nombre del módulo."
  def start_link(_opts \\ []) do
    pid = spawn_link(&iniciar/0)
    Process.register(pid, @nombre)
    {:ok, pid}
  end

  @doc "Registra una acción de un usuario. Es asíncrona: no espera respuesta."
  def registrar(usuario, accion) do
    enviar({:registrar, to_string(usuario), to_string(accion)})
  end

  @doc "Devuelve la actividad de un usuario (o de todos con `:todos`), de la más reciente a la más antigua."
  def consultar(usuario \\ :todos) do
    ref = make_ref()

    with :ok <- enviar({:consultar, self(), ref, usuario}) do
      receive do
        {^ref, entradas} -> {:ok, entradas}
      after
        @tiempo_espera -> {:error, :tiempo_agotado}
      end
    end
  end

  defp enviar(mensaje) do
    case Process.whereis(@nombre) do
      nil ->
        {:error, :logger_no_disponible}

      pid ->
        send(pid, mensaje)
        :ok
    end
  end

  defp iniciar do
    {:ok, entradas} = Persistencia.cargar(@archivo, &desde_linea/1)
    loop(Enum.reverse(entradas))
  end

  # Ciclo del proceso: atiende un mensaje y se vuelve a llamar con el nuevo estado. Recursiva.
  defp loop(entradas) do
    receive do
      {:registrar, usuario, accion} ->
        entrada = {Fechas.ahora(), usuario, accion}
        Persistencia.agregar_linea(@archivo, a_linea(entrada))
        loop([entrada | entradas])

      {:consultar, de, ref, usuario} ->
        send(de, {ref, filtrar(entradas, usuario)})
        loop(entradas)

      _desconocido ->
        loop(entradas)
    end
  end

  defp filtrar(entradas, :todos), do: entradas

  defp filtrar(entradas, usuario),
    do: Enum.filter(entradas, fn {_, u, _} -> u == to_string(usuario) end)

  defp a_linea({fecha, usuario, accion}) do
    Persistencia.unir_campos([Fechas.formatear(fecha), usuario, accion])
  end

  defp desde_linea(linea) do
    with [texto_fecha, usuario, accion] <- Persistencia.separar_campos(linea),
         {:ok, fecha} <- Fechas.desde_texto(texto_fecha) do
      {:ok, {fecha, usuario, accion}}
    else
      _ -> {:error, :linea_invalida}
    end
  end
end
