defmodule Emergencias.CLI do
  @moduledoc """
  Consola del sistema: lee comandos, los ejecuta y muestra el resultado.
  """

  alias Emergencias.CLI.{Dispatcher, Formatter, Parser}

  @doc "Inicia la consola."
  def iniciar do
    IO.puts("Sistema de Gestión de Emergencias. Escribe help para ver los comandos.")
    loop(nil)
  end

  # Lee un comando, lo procesa y se vuelve a llamar con la sesión actualizada. Recursiva.
  defp loop(sesion) do
    case leer_linea(sesion) do
      :fin ->
        IO.puts("Hasta luego.")

      linea ->
        case procesar(linea, sesion) do
          {:salir, _} ->
            IO.puts("Hasta luego.")

          {texto, nueva_sesion} ->
            if texto != "", do: IO.puts(texto)
            loop(nueva_sesion)
        end
    end
  end

  defp leer_linea(sesion) do
    case IO.gets(prompt(sesion)) do
      texto when is_binary(texto) -> texto
      _ -> :fin
    end
  end

  defp prompt(nil), do: "> "
  defp prompt(%{usuario: usuario}), do: "#{usuario}> "

  @doc "Procesa una línea y devuelve `{texto, sesion}` o `{:salir, sesion}`."
  def procesar(linea, sesion) do
    if String.trim(linea) == "" do
      {"", sesion}
    else
      case Parser.parsear(linea) do
        {:ok, comando} ->
          case Dispatcher.despachar(comando, sesion) do
            {:salir, sesion} -> {:salir, sesion}
            {resultado, nueva_sesion} -> {Formatter.formatear(resultado), nueva_sesion}
          end

        error ->
          {Formatter.formatear(error), sesion}
      end
    end
  end
end
