defmodule Emergencias.Application do
  @moduledoc """
  Arranca el sistema: prepara los datos y levanta el árbol de supervisión.
  """

  use Application

  alias Emergencias.Persistencia

  @impl true
  def start(_type, _args) do
    Persistencia.cargar_datos_iniciales()

    # Cada una quita el # de su línea cuando su módulo exista.
    children = [
      {Registry, keys: :unique, name: Emergencias.Registry},
      Emergencias.Servidores.ActividadLogger,
      Emergencias.Servidores.UsuarioServer,
      Emergencias.Servidores.SesionSupervisor,
      Emergencias.Servidores.ZonaServer,
      Emergencias.Servidores.InventarioServer,
      Emergencias.Servidores.NecesidadServer,
      Emergencias.Servidores.FamiliaServer,
      Emergencias.Servidores.MascotaServer,
      Emergencias.Servidores.AlbergueSupervisor
    ]

    opts = [strategy: :one_for_one, name: Emergencias.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
