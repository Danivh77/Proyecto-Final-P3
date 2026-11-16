defmodule Emergencias.Dominio.ReporteMascota do
  @moduledoc """
  Dominio puro de un reporte de mascota perdida o encontrada.

  """

  alias Emergencias.Persistencia

  defstruct [
    :id,
    :tipo,
    :especie,
    :nombre,
    :caracteristicas,
    :color,
    :tamano,
    :zona,
    :contacto,
    :coincidencia_con,
    estado: :activa
  ]

  @type tipo :: :perdida | :encontrada
  @type estado :: :activa | :posible_coincidencia | :resuelta

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: tipo(),
          especie: String.t(),
          nombre: String.t(),
          caracteristicas: String.t(),
          color: String.t(),
          tamano: String.t(),
          zona: String.t(),
          contacto: String.t(),
          estado: estado(),
          coincidencia_con: String.t() | nil
        }

  @estados [:activa, :posible_coincidencia, :resuelta]

  @doc "Convierte `lost/perdida` y `found/encontrada` (o el átomo) en un tipo válido."
  @spec tipo_desde_texto(term()) :: {:ok, tipo()} | {:error, :tipo_invalido}
  def tipo_desde_texto(tipo) when tipo in [:perdida, :encontrada], do: {:ok, tipo}

  def tipo_desde_texto(texto) when is_binary(texto) do
    case normalizar(texto) do
      t when t in ["lost", "perdida", "perdido"] -> {:ok, :perdida}
      t when t in ["found", "encontrada", "encontrado"] -> {:ok, :encontrada}
      _ -> {:error, :tipo_invalido}
    end
  end

  def tipo_desde_texto(_), do: {:error, :tipo_invalido}

  @doc "Convierte un texto (`\"posible coincidencia\"`, `\"activa\"`...) o átomo en estado válido."
  @spec estado_desde_texto(term()) :: {:ok, estado()} | {:error, :estado_invalido}
  def estado_desde_texto(estado) when estado in @estados, do: {:ok, estado}

  def estado_desde_texto(texto) when is_binary(texto) do
    normalizado = texto |> normalizar() |> String.replace(~r/[\s-]+/, "_")

    case Enum.find(@estados, &(Atom.to_string(&1) == normalizado)) do
      nil -> {:error, :estado_invalido}
      estado -> {:ok, estado}
    end
  end

  def estado_desde_texto(_), do: {:error, :estado_invalido}

  @doc "Minúsculas, sin espacios sobrantes y sin tildes (para comparar textos)."
  @spec normalizar(String.t() | nil) :: String.t()
  def normalizar(nil), do: ""

  def normalizar(texto) when is_binary(texto) do
    texto
    |> String.downcase()
    |> String.trim()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  @doc """
  Crea un reporte `:activa`. El nombre y las características son opcionales
  (`nil` o vacío: el nombre queda como `"desconocido"`).

  Errores: `:datos_invalidos`, `:tipo_invalido`.
  """
  @spec nuevo(term(), term(), term(), term(), term(), term(), term(), term(), term()) ::
          {:ok, t()} | {:error, atom()}
  def nuevo(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    id = limpiar(id)
    especie = limpiar(especie)
    color = limpiar(color)
    tamano = limpiar(tamano)
    zona = limpiar(zona)
    contacto = limpiar(contacto)
    nombre = opcional(nombre, "desconocido")
    caracteristicas = opcional(caracteristicas, "")

    obligatorios = [id, especie, color, tamano, zona, contacto]

    cond do
      not Enum.all?(obligatorios, &texto_valido?/1) ->
        {:error, :datos_invalidos}

      not (texto_seguro?(nombre) and texto_seguro?(caracteristicas)) ->
        {:error, :datos_invalidos}

      true ->
        with {:ok, tipo} <- tipo_desde_texto(tipo) do
          {:ok,
           %__MODULE__{
             id: id,
             tipo: tipo,
             especie: especie,
             nombre: nombre,
             caracteristicas: caracteristicas,
             color: color,
             tamano: tamano,
             zona: zona,
             contacto: contacto
           }}
        end
    end
  end

  @doc """
  Marca el reporte como posible coincidencia con otro (`id_otro`). Puede repetirse para
  actualizar la coincidencia. Error: `:ya_resuelto`.
  """
  @spec marcar_posible(t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def marcar_posible(%__MODULE__{estado: :resuelta}, _id_otro), do: {:error, :ya_resuelto}

  def marcar_posible(%__MODULE__{} = reporte, id_otro)
      when is_binary(id_otro) and id_otro != "" do
    {:ok, %{reporte | estado: :posible_coincidencia, coincidencia_con: id_otro}}
  end

  def marcar_posible(%__MODULE__{}, _id_otro), do: {:error, :datos_invalidos}

  @doc "Cierra el reporte registrando con quién coincidió. Error: `:ya_resuelto` si ya estaba cerrado."
  @spec resolver(t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def resolver(%__MODULE__{estado: :resuelta}, _id_otro), do: {:error, :ya_resuelto}

  def resolver(%__MODULE__{} = reporte, id_otro) when is_binary(id_otro) and id_otro != "" do
    {:ok, %{reporte | estado: :resuelta, coincidencia_con: id_otro}}
  end

  def resolver(%__MODULE__{}, _id_otro), do: {:error, :datos_invalidos}

  @doc """
  Filtra una lista de reportes por `:especie`, `:zona`, `:estado` y/o `:tipo`
  (keyword list o mapa). Los filtros en `nil` y las claves desconocidas se ignoran.
  """
  @spec filtrar([t()], keyword() | map()) :: [t()]
  def filtrar(reportes, filtros) do
    Enum.filter(reportes, fn reporte -> Enum.all?(filtros, &cumple?(reporte, &1)) end)
  end

  defp cumple?(_reporte, {_clave, nil}), do: true
  defp cumple?(reporte, {:especie, v}), do: normalizar(reporte.especie) == normalizar_texto(v)
  defp cumple?(reporte, {:zona, v}), do: normalizar(reporte.zona) == normalizar_texto(v)
  defp cumple?(reporte, {:estado, v}), do: estado_desde_texto(v) == {:ok, reporte.estado}
  defp cumple?(reporte, {:tipo, v}), do: tipo_desde_texto(v) == {:ok, reporte.tipo}
  defp cumple?(_reporte, _otro), do: true

  defp normalizar_texto(valor) when is_binary(valor), do: normalizar(valor)
  defp normalizar_texto(_), do: nil

  @doc "Convierte el reporte a una línea de texto."
  @spec a_linea(t()) :: String.t()
  def a_linea(%__MODULE__{} = r) do
    Persistencia.unir_campos([
      r.id,
      r.tipo,
      r.especie,
      r.nombre,
      r.caracteristicas,
      r.color,
      r.tamano,
      r.zona,
      r.contacto,
      r.estado,
      r.coincidencia_con
    ])
  end

  @doc "Reconstruye un reporte desde una línea. Devuelve `{:error, :linea_invalida}` si está dañada."
  @spec desde_linea(String.t()) :: {:ok, t()} | {:error, :linea_invalida}
  def desde_linea(linea) when is_binary(linea) do
    with [id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, estado, otro] <-
           linea |> String.trim() |> Persistencia.separar_campos(),
         {:ok, reporte} <-
           nuevo(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto),
         {:ok, estado} <- estado_desde_texto(estado) do
      {:ok, %{reporte | estado: estado, coincidencia_con: if(otro == "", do: nil, else: otro)}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp limpiar(valor) when is_binary(valor), do: String.trim(valor)
  defp limpiar(_), do: nil

  defp opcional(nil, por_defecto), do: por_defecto

  defp opcional(valor, por_defecto) when is_binary(valor) do
    case String.trim(valor) do
      "" -> por_defecto
      limpio -> limpio
    end
  end

  defp opcional(_, _), do: nil

  # Texto libre: no vacío y sin saltos de línea (el `|` se escapa al guardar).
  defp texto_valido?(valor) when is_binary(valor), do: Regex.match?(~r/^[^\r\n]+$/, valor)
  defp texto_valido?(_), do: false

  # Como `texto_valido?/1` pero admite vacío (campos opcionales).
  defp texto_seguro?(valor) when is_binary(valor),
    do: not String.contains?(valor, ["\r", "\n"])

  defp texto_seguro?(_), do: false
end
