defmodule Emergencias.Dominio.Mensaje do
  @moduledoc """
  Dominio puro de un mensaje dirigido a una persona o familia.

  """

  alias Emergencias.Persistencia

  defstruct [:id, :fecha, :remitente, :destinatario, :contenido, estado: :pendiente]

  @type estado :: :pendiente | :entregado

  @type t :: %__MODULE__{
          id: String.t() | nil,
          fecha: String.t() | nil,
          remitente: String.t(),
          destinatario: String.t(),
          contenido: String.t(),
          estado: estado()
        }

  @max_contenido 500

  @doc """
  Crea un mensaje `:pendiente`. El `id` y la `fecha` los asigna quien lo guarda
  (el servidor) mediante las opciones `:id` y `:fecha`; si no se dan quedan en `nil`.

  Errores: `:remitente_invalido`, `:destinatario_invalido`, `:contenido_invalido`.
  """
  @spec nuevo(term(), term(), term(), keyword()) :: {:ok, t()} | {:error, atom()}
  def nuevo(remitente, destinatario, contenido, opciones \\ []) do
    remitente = limpiar(remitente)
    destinatario = limpiar(destinatario)
    contenido = limpiar(contenido)

    cond do
      not no_vacio?(remitente) ->
        {:error, :remitente_invalido}

      not no_vacio?(destinatario) ->
        {:error, :destinatario_invalido}

      not contenido_valido?(contenido) ->
        {:error, :contenido_invalido}

      true ->
        {:ok,
         %__MODULE__{
           id: Keyword.get(opciones, :id),
           fecha: Keyword.get(opciones, :fecha),
           remitente: remitente,
           destinatario: destinatario,
           contenido: contenido,
           estado: :pendiente
         }}
    end
  end

  @doc "Marca el mensaje como entregado. Error: `:ya_entregado`."
  @spec marcar_entregado(t()) :: {:ok, t()} | {:error, :ya_entregado}
  def marcar_entregado(%__MODULE__{estado: :entregado}), do: {:error, :ya_entregado}
  def marcar_entregado(%__MODULE__{} = mensaje), do: {:ok, %{mensaje | estado: :entregado}}

  @doc "Marca el mensaje como pendiente. Error: `:ya_pendiente`."
  @spec marcar_pendiente(t()) :: {:ok, t()} | {:error, :ya_pendiente}
  def marcar_pendiente(%__MODULE__{estado: :pendiente}), do: {:error, :ya_pendiente}
  def marcar_pendiente(%__MODULE__{} = mensaje), do: {:ok, %{mensaje | estado: :pendiente}}

  @doc "Convierte un texto (`\"entregado\"`, `\"pendiente\"`) o átomo en estado válido."
  @spec estado_desde_texto(term()) :: {:ok, estado()} | {:error, :estado_invalido}
  def estado_desde_texto(estado) when estado in [:pendiente, :entregado], do: {:ok, estado}

  def estado_desde_texto(texto) when is_binary(texto) do
    case texto |> String.trim() |> String.downcase() do
      "pendiente" -> {:ok, :pendiente}
      "entregado" -> {:ok, :entregado}
      _ -> {:error, :estado_invalido}
    end
  end

  def estado_desde_texto(_), do: {:error, :estado_invalido}

  @doc "Convierte el mensaje a una línea de texto (escapando `|`, `\\` y saltos de línea)."
  @spec a_linea(t()) :: String.t()
  def a_linea(%__MODULE__{} = m) do
    Persistencia.unir_campos([m.id, m.fecha, m.remitente, m.destinatario, m.contenido, m.estado])
  end

  @doc "Reconstruye un mensaje desde una línea. Devuelve `{:error, :linea_invalida}` si está dañada."
  @spec desde_linea(String.t()) :: {:ok, t()} | {:error, :linea_invalida}
  def desde_linea(linea) when is_binary(linea) do
    with [id, fecha, remitente, destinatario, contenido, estado] <-
           linea |> String.trim() |> Persistencia.separar_campos(),
         {:ok, estado} <- estado_desde_texto(estado),
         {:ok, mensaje} <-
           nuevo(remitente, destinatario, contenido,
             id: vacio_a_nil(id),
             fecha: vacio_a_nil(fecha)
           ) do
      {:ok, %{mensaje | estado: estado}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp vacio_a_nil(""), do: nil
  defp vacio_a_nil(texto), do: texto

  # Quita espacios sobrantes y los "\r" (que `unir_campos/1` no escapa).
  defp limpiar(valor) when is_binary(valor),
    do: valor |> String.replace("\r", "") |> String.trim()

  defp limpiar(_), do: nil

  defp no_vacio?(valor), do: is_binary(valor) and valor != ""

  defp contenido_valido?(valor) do
    no_vacio?(valor) and String.length(valor) <= @max_contenido
  end
end
