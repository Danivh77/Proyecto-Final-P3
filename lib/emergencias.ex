defmodule Emergencias do
  @moduledoc """
  Sistema Distribuido de Coordinación y Gestión de Emergencias.

  Para usarlo: `iex -S mix` y luego `Emergencias.iniciar()`.
  """

  @doc "Inicia la consola de comandos."
  def iniciar, do: Emergencias.CLI.iniciar()
end
