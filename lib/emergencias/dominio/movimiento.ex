defmodule Emergencias.Dominio.Movimiento do
  @moduledoc "Registro de una operación de inventario para su historial."

  alias Emergencias.Persistencia
  alias Emergencias.Util.Fechas

  @tipos ~w(entrada salida asignacion transferencia)

  defstruct [:fecha, :tipo, :recurso, :cantidad, :referencia, :usuario]

  @doc """
  Crea un movimiento con la fecha y hora actuales. El recurso se indica por su código.
  La referencia es texto opcional, por ejemplo el ID de una necesidad o el destino.
  """
  def nuevo(tipo, recurso, cantidad, referencia, usuario) do
    construir(Fechas.ahora(), tipo, recurso, cantidad, referencia, usuario)
  end

  @doc "Convierte el movimiento en una línea de texto."
  def a_linea(%__MODULE__{} = movimiento) do
    Persistencia.unir_campos([
      Fechas.formatear(movimiento.fecha),
      movimiento.tipo,
      movimiento.recurso,
      movimiento.cantidad,
      movimiento.referencia,
      movimiento.usuario
    ])
  end

  @doc "Recupera el movimiento y conserva la fecha registrada."
  def desde_linea(linea) when is_binary(linea) do
    with [fecha, tipo, recurso, texto, referencia, usuario] <- Persistencia.separar_campos(linea),
         {:ok, fecha} <- Fechas.desde_texto(fecha),
         {cantidad, ""} <- Integer.parse(texto),
         {:ok, movimiento} <- construir(fecha, tipo, recurso, cantidad, referencia, usuario) do
      {:ok, movimiento}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp construir(fecha, tipo, recurso, cantidad, referencia, usuario) do
    cond do
      tipo not in @tipos ->
        {:error, :tipo_movimiento_invalido}

      vacio?(recurso) ->
        {:error, :codigo_invalido}

      not is_integer(cantidad) or cantidad <= 0 ->
        {:error, :cantidad_invalida}

      not is_nil(referencia) and not is_binary(referencia) ->
        {:error, :referencia_invalida}

      vacio?(usuario) ->
        {:error, :usuario_invalido}

      true ->
        {:ok,
         %__MODULE__{
           fecha: fecha,
           tipo: tipo,
           recurso: String.trim(recurso),
           cantidad: cantidad,
           referencia: if(referencia == "", do: nil, else: referencia),
           usuario: usuario
         }}
    end
  end

  defp vacio?(texto) when is_binary(texto), do: String.trim(texto) == ""
  defp vacio?(_), do: true
end
