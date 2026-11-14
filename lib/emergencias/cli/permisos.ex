defmodule Emergencias.CLI.Permisos do
  @moduledoc """
  Define qué puede hacer cada tipo de usuario.
  Cada tipo puede hacer lo suyo y todo lo de los tipos anteriores:
  ciudadano < voluntario < coordinador < administrador.
  """

  alias Emergencias.CLI.Parser

  @voluntario ~w(register_resource resource_entry resource_exit resource_history
                 register_entry register_exit update_person update_need mark_message
                 match_pets pending_needs critical_resources shelter_report)a

  @coordinador ~w(register_zone register_sector register_point register_shelter
                  assign_resource transfer_resource confirm_match summary)a

  @administrador ~w(activity_log)a

  @doc "Indica si un tipo de usuario puede ejecutar un comando."
  def puede?(tipo, comando), do: nivel(tipo) >= nivel(rol_minimo(comando))

  @doc "Tipo de usuario mínimo que necesita un comando."
  def rol_minimo(comando) when comando in @administrador, do: "administrador"
  def rol_minimo(comando) when comando in @coordinador, do: "coordinador"
  def rol_minimo(comando) when comando in @voluntario, do: "voluntario"
  def rol_minimo(_comando), do: "ciudadano"

  @doc "Comandos que puede ejecutar un tipo de usuario."
  def acciones_de(tipo) do
    Parser.comandos()
    |> Enum.map(&String.to_atom/1)
    |> Enum.filter(&puede?(tipo, &1))
  end

  defp nivel("ciudadano"), do: 1
  defp nivel("voluntario"), do: 2
  defp nivel("coordinador"), do: 3
  defp nivel("administrador"), do: 4
  defp nivel(_), do: 0
end
