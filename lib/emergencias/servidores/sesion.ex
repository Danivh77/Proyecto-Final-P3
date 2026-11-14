defmodule Emergencias.Servidores.Sesion do
  @moduledoc """
  Proceso de un usuario conectado. Guarda sus datos y los comandos de la sesión.
  Se encuentra por el nombre del usuario mediante el `Registry`.
  """

  use GenServer, restart: :temporary

  alias Emergencias.Util.Fechas

  @doc "Inicia la sesión con `%{usuario: _, tipo: _, zona: _}`."
  def start_link(%{usuario: usuario} = datos) do
    GenServer.start_link(__MODULE__, datos, name: via(usuario))
  end

  @doc "Nombre del proceso dentro del Registry."
  def via(usuario), do: {:via, Registry, {Emergencias.Registry, {:sesion, usuario}}}

  @doc "Datos de la sesión."
  def info(usuario), do: llamar(usuario, :info)

  @doc "Guarda un comando en el historial de la sesión."
  def registrar_comando(usuario, comando), do: GenServer.cast(via(usuario), {:registrar, comando})

  @doc "Comandos de la sesión, del más reciente al más antiguo."
  def historial(usuario), do: llamar(usuario, :historial)

  defp llamar(usuario, mensaje) do
    case Registry.lookup(Emergencias.Registry, {:sesion, usuario}) do
      [{pid, _}] -> {:ok, GenServer.call(pid, mensaje)}
      [] -> {:error, :no_conectado}
    end
  end

  @impl true
  def init(datos) do
    {:ok, Map.merge(datos, %{inicio: Fechas.ahora(), comandos: []})}
  end

  @impl true
  def handle_call(:info, _from, estado), do: {:reply, Map.delete(estado, :comandos), estado}
  def handle_call(:historial, _from, estado), do: {:reply, estado.comandos, estado}

  @impl true
  def handle_cast({:registrar, comando}, estado) do
    {:noreply, %{estado | comandos: [{Fechas.ahora(), comando} | estado.comandos]}}
  end
end
