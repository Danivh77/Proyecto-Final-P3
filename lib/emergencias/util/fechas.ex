defmodule Emergencias.Util.Fechas do
  @moduledoc """
  Fecha y hora para historiales, mensajes y movimientos.
  Se usa la hora local del computador y el formato `AAAA-MM-DD HH:MM:SS`.
  """

  @doc "Fecha y hora actual, sin microsegundos."
  def ahora do
    NaiveDateTime.local_now()
    |> NaiveDateTime.truncate(:second)
  end

  @doc "Convierte una fecha a texto: `2026-11-14 13:53:00`."
  def formatear(%NaiveDateTime{} = fecha), do: NaiveDateTime.to_string(fecha)

  @doc "Convierte un texto guardado en un archivo de vuelta a fecha."
  def desde_texto(texto) when is_binary(texto) do
    case NaiveDateTime.from_iso8601(texto) do
      {:ok, fecha} -> {:ok, fecha}
      {:error, _} -> {:error, :fecha_invalida}
    end
  end
end
