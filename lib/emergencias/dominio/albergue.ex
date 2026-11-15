defmodule Emergencias.Dominio.Albergue do
  @moduledoc """
  Dominio puro de un albergue: capacidad, ocupantes, recursos y necesidades asociadas.


  """

  alias Emergencias.Persistencia

  defstruct [
    :codigo,
    :nombre,
    :zona,
    :capacidad,
    ocupantes: MapSet.new(),
    recursos: [],
    necesidades: []
  ]

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          zona: String.t(),
          capacidad: pos_integer(),
          ocupantes: MapSet.t(String.t()),
          recursos: [String.t()],
          necesidades: [String.t()]
        }


  @doc """
  Crea un albergue vacío.

  """
  @spec nuevo(term(), term(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def nuevo(codigo, nombre, zona, capacidad) do
    codigo = limpiar(codigo)
    nombre = limpiar(nombre)
    zona = limpiar(zona)

    cond do
      not codigo_valido?(codigo) ->
        {:error, :codigo_invalido}

      not texto_valido?(nombre) or not texto_valido?(zona) ->
        {:error, :datos_invalidos}

      not (is_integer(capacidad) and capacidad > 0) ->
        {:error, :capacidad_invalida}

      true ->
        {:ok,
         %__MODULE__{
           codigo: String.upcase(codigo),
           nombre: nombre,
           zona: zona,
           capacidad: capacidad
         }}
    end
  end

  @doc "Normaliza un código de albergue (quita espacios y pasa a mayúsculas)."
  @spec normalizar_codigo(term()) :: String.t() | nil
  def normalizar_codigo(codigo) when is_binary(codigo),
    do: codigo |> String.trim() |> String.upcase()

  def normalizar_codigo(_), do: nil

  @doc "Número de personas dentro del albergue."
  @spec ocupacion(t()) :: non_neg_integer()
  def ocupacion(%__MODULE__{ocupantes: ocupantes}), do: MapSet.size(ocupantes)

  @doc "Cupos libres (nunca negativo)."
  @spec cupos(t()) :: non_neg_integer()
  def cupos(%__MODULE__{capacidad: capacidad} = albergue),
    do: max(capacidad - ocupacion(albergue), 0)

  @doc "Porcentaje de ocupación con un decimal (0.0 a 100.0)."
  @spec porcentaje_ocupacion(t()) :: float()
  def porcentaje_ocupacion(%__MODULE__{capacidad: capacidad} = albergue) do
    Float.round(ocupacion(albergue) * 100 / capacidad, 1)
  end

  @doc """
  Registra el ingreso de una persona (por documento).

  """
  @spec ingresar(t(), term()) :: {:ok, t()} | {:error, atom()}
  def ingresar(%__MODULE__{} = albergue, documento) do
    documento = limpiar(documento)

    cond do
      not documento_valido?(documento) -> {:error, :documento_invalido}
      MapSet.member?(albergue.ocupantes, documento) -> {:error, :ya_esta_dentro}
      ocupacion(albergue) >= albergue.capacidad -> {:error, :capacidad_llena}
      true -> {:ok, %{albergue | ocupantes: MapSet.put(albergue.ocupantes, documento)}}
    end
  end

  @doc "Registra la salida de una persona. Errores: `:documento_invalido`, `:no_esta_dentro`."
  @spec salir(t(), term()) :: {:ok, t()} | {:error, atom()}
  def salir(%__MODULE__{} = albergue, documento) do
    documento = limpiar(documento)

    cond do
      not documento_valido?(documento) -> {:error, :documento_invalido}
      not MapSet.member?(albergue.ocupantes, documento) -> {:error, :no_esta_dentro}
      true -> {:ok, %{albergue | ocupantes: MapSet.delete(albergue.ocupantes, documento)}}
    end
  end

  @doc "Asocia el código de un recurso al albergue. Errores: `:datos_invalidos`, `:ya_asociado`."
  @spec asociar_recurso(t(), term()) :: {:ok, t()} | {:error, atom()}
  def asociar_recurso(%__MODULE__{} = albergue, codigo_recurso) do
    with {:ok, lista} <- agregar_unico(albergue.recursos, codigo_recurso) do
      {:ok, %{albergue | recursos: lista}}
    end
  end

  @doc "Asocia el id de una necesidad al albergue. Errores: `:datos_invalidos`, `:ya_asociado`."
  @spec asociar_necesidad(t(), term()) :: {:ok, t()} | {:error, atom()}
  def asociar_necesidad(%__MODULE__{} = albergue, id_necesidad) do
    with {:ok, lista} <- agregar_unico(albergue.necesidades, id_necesidad) do
      {:ok, %{albergue | necesidades: lista}}
    end
  end


  @doc "Convierte el albergue a una línea de texto."
  @spec a_linea(t()) :: String.t()
  def a_linea(%__MODULE__{} = albergue) do
    Persistencia.unir_campos([
      albergue.codigo,
      albergue.nombre,
      albergue.zona,
      albergue.capacidad,
      albergue.ocupantes |> Enum.sort() |> Enum.join(","),
      Enum.join(albergue.recursos, ","),
      Enum.join(albergue.necesidades, ",")
    ])
  end

  @doc "Reconstruye un albergue desde una línea. Devuelve `{:error, :linea_invalida}` si está dañada."
  @spec desde_linea(String.t()) :: {:ok, t()} | {:error, :linea_invalida}
  def desde_linea(linea) when is_binary(linea) do
    with [codigo, nombre, zona, capacidad, ocupantes, recursos, necesidades] <-
           linea |> String.trim() |> Persistencia.separar_campos(),
         {capacidad, ""} <- Integer.parse(capacidad),
         {:ok, albergue} <- nuevo(codigo, nombre, zona, capacidad),
         ocupantes = MapSet.new(dividir(ocupantes)),
         true <- Enum.all?(ocupantes, &documento_valido?/1),
         true <- MapSet.size(ocupantes) <= capacidad do
      {:ok,
       %{
         albergue
         | ocupantes: ocupantes,
           recursos: dividir(recursos),
           necesidades: dividir(necesidades)
       }}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp agregar_unico(lista, valor) do
    valor = limpiar(valor)

    cond do
      not documento_valido?(valor) -> {:error, :datos_invalidos}
      valor in lista -> {:error, :ya_asociado}
      true -> {:ok, lista ++ [valor]}
    end
  end

  defp dividir(texto), do: String.split(texto, ",", trim: true)

  defp limpiar(valor) when is_binary(valor), do: String.trim(valor)
  defp limpiar(_), do: nil

  defp codigo_valido?(valor) when is_binary(valor), do: Regex.match?(~r/^[A-Za-z0-9_-]+$/, valor)
  defp codigo_valido?(_), do: false

  # Texto libre: no vacío y sin saltos de línea. El carácter `|` sí se admite porque
  # `Persistencia.unir_campos/1` lo escapa al guardar.
  defp texto_valido?(valor) when is_binary(valor), do: Regex.match?(~r/^[^\r\n]+$/, valor)
  defp texto_valido?(_), do: false

  # Documento / código de referencia: además no puede contener `,` (separa listas).
  defp documento_valido?(valor) when is_binary(valor), do: Regex.match?(~r/^[^|,;>\r\n]+$/, valor)
  defp documento_valido?(_), do: false
end
