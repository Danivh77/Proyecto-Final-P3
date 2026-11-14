defmodule Emergencias.Servidores.SesionSupervisor do
  @moduledoc """
  DynamicSupervisor que crea un proceso `Sesion` por cada usuario conectado
  y lo termina cuando se desconecta.
  """

  use DynamicSupervisor

  alias Emergencias.Servidores.Sesion

  def start_link(_opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Crea la sesión de un usuario."
  def iniciar_sesion(%{usuario: _} = datos) do
    case DynamicSupervisor.start_child(__MODULE__, {Sesion, datos}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :ya_conectado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc "Termina la sesión de un usuario."
  def cerrar_sesion(usuario) do
    case Registry.lookup(Emergencias.Registry, {:sesion, usuario}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :no_conectado}
    end
  end

  @doc "Usuarios con una sesión activa."
  def sesiones_activas do
    Emergencias.Registry
    |> Registry.select([{{{:sesion, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end
end
