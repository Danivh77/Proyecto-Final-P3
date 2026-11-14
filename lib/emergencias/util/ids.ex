defmodule Emergencias.Util.Ids do
  @moduledoc """
  Genera identificadores con prefijo y número, por ejemplo `N001`, `R002` o `MSG003`.
  """

  @digitos 3

  @doc """
  Devuelve el siguiente ID libre para el prefijo.
  `existentes` puede ser una lista de IDs o un mapa cuyas llaves son los IDs.

      siguiente("N", ["N001", "N002"])   #=> "N003"
      siguiente("N", %{})                #=> "N001"
  """
  def siguiente(prefijo, existentes) when is_binary(prefijo) and is_map(existentes) do
    siguiente(prefijo, Map.keys(existentes))
  end

  def siguiente(prefijo, existentes) when is_binary(prefijo) and is_list(existentes) do
    numero = mayor_numero(prefijo, existentes, 0) + 1
    formatear(prefijo, numero)
  end

  @doc "Arma un ID con el número rellenado con ceros: `formatear(\"R\", 7)` da `\"R007\"`."
  def formatear(prefijo, numero) when is_binary(prefijo) and is_integer(numero) and numero > 0 do
    prefijo <> String.pad_leading(Integer.to_string(numero), @digitos, "0")
  end

  @doc "Indica si un ID ya está en uso."
  def existe?(id, existentes) when is_map(existentes), do: Map.has_key?(existentes, id)
  def existe?(id, existentes) when is_list(existentes), do: id in existentes

  # Recorre los IDs y se queda con el número más alto del prefijo. Recursiva.
  defp mayor_numero(_prefijo, [], mayor), do: mayor

  defp mayor_numero(prefijo, [id | resto], mayor) do
    case numero_de(prefijo, id) do
      {:ok, n} when n > mayor -> mayor_numero(prefijo, resto, n)
      _ -> mayor_numero(prefijo, resto, mayor)
    end
  end

  # "N012" con prefijo "N" da {:ok, 12}; si el ID no es de ese prefijo da :error.
  defp numero_de(prefijo, id) when is_binary(id) do
    with true <- String.starts_with?(id, prefijo),
         {n, ""} <- Integer.parse(String.replace_prefix(id, prefijo, "")) do
      {:ok, n}
    else
      _ -> :error
    end
  end

  defp numero_de(_prefijo, _id), do: :error
end
