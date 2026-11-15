defmodule Emergencias.CLI.Parser do
  @moduledoc """
  Convierte el texto que escribe el usuario en un comando `{nombre, argumentos}`.
  Los argumentos quedan como texto; cada comando los valida en el dispatcher.

      parsear(~s(send_family_message 1094 "Estoy bien"))
      #=> {:ok, {:send_family_message, ["1094", "Estoy bien"]}}
  """

  @comandos ~w(
    connect disconnect summary help activity_log exit

    register_zone register_sector register_point zone_status zone_stats
    register_need list_needs update_need assign_resource pending_needs
    register_resource resource_entry resource_exit list_resources
    transfer_resource resource_history critical_resources

    register_shelter check_shelter list_shelters register_entry register_exit
    shelter_report report_person find_person search_persons update_person
    person_history send_family_message list_family_messages mark_message
    report_pet list_pets match_pets confirm_match
  )

  @filtros ~w(zona prioridad estado tipo especie categoria nombre documento ubicacion albergue)

  @doc "Lista de nombres de comandos válidos."
  def comandos, do: @comandos

  @doc "Convierte una línea de texto en `{:ok, {comando, argumentos}}` o `{:error, motivo}`."
  def parsear(linea) when is_binary(linea) do
    case tokenizar(String.trim(linea)) do
      {:ok, []} -> {:error, :comando_vacio}
      {:ok, [nombre | args]} -> a_comando(String.downcase(nombre), args)
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp a_comando(nombre, args) when nombre in @comandos, do: {:ok, {String.to_atom(nombre), args}}
  defp a_comando(nombre, _args), do: {:error, {:comando_desconocido, nombre}}

  @doc "Separa el texto en palabras; lo que está entre comillas queda como una sola. Recursiva."
  def tokenizar(texto) when is_binary(texto) do
    tokenizar(String.graphemes(texto), "", [], false)
  end

  defp tokenizar([], _actual, _tokens, true), do: {:error, :comillas_sin_cerrar}
  defp tokenizar([], "", tokens, false), do: {:ok, Enum.reverse(tokens)}
  defp tokenizar([], actual, tokens, false), do: {:ok, Enum.reverse([actual | tokens])}

  defp tokenizar(["\"" | resto], actual, tokens, false),
    do: tokenizar(resto, actual, tokens, true)

  defp tokenizar(["\"" | resto], actual, tokens, true),
    do: tokenizar(resto, "", [actual | tokens], false)

  defp tokenizar([c | resto], actual, tokens, false) when c in [" ", "\t"] do
    case actual do
      "" -> tokenizar(resto, "", tokens, false)
      _ -> tokenizar(resto, "", [actual | tokens], false)
    end
  end

  defp tokenizar([c | resto], actual, tokens, entre_comillas),
    do: tokenizar(resto, actual <> c, tokens, entre_comillas)

  @doc """
  Convierte argumentos como `zona=centro prioridad=critica` en una keyword list.

      parsear_filtros(["zona=centro"])   #=> {:ok, [zona: "centro"]}
  """
  def parsear_filtros(args) when is_list(args) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, filtros} ->
      case String.split(arg, "=", parts: 2) do
        [clave, valor] when clave in @filtros and valor != "" ->
          {:cont, {:ok, filtros ++ [{String.to_atom(clave), valor}]}}

        _ ->
          {:halt, {:error, {:filtro_invalido, arg}}}
      end
    end)
  end

  @doc "Convierte un texto en entero."
  def a_entero(texto) when is_binary(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, {:numero_invalido, texto}}
    end
  end

  @doc "Convierte un texto en entero mayor que cero (para cantidades y capacidades)."
  def a_entero_positivo(texto) when is_binary(texto) do
    case a_entero(texto) do
      {:ok, numero} when numero > 0 -> {:ok, numero}
      _ -> {:error, {:cantidad_invalida, texto}}
    end
  end
end
