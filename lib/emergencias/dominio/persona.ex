defmodule Emergencias.Dominio.Persona do
  @moduledoc """
  Dominio puro de una persona afectada por el terremoto.

  """

  alias Emergencias.Persistencia

  defstruct [:id, :documento, :nombre, :edad, :zona, :estado, historial: []]

  @type estado ::
          :sin_informacion | :reportada | :localizada | :trasladada | :en_albergue | :reunificada

  @type t :: %__MODULE__{
          id: String.t(),
          documento: String.t(),
          nombre: String.t(),
          edad: non_neg_integer() | nil,
          zona: String.t(),
          estado: estado(),
          historial: [{String.t(), estado(), estado()}]
        }

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  # Transiciones permitidas. `:reunificada` es un estado final.
  @transiciones %{
    sin_informacion: [:reportada, :localizada, :trasladada, :en_albergue],
    reportada: [:sin_informacion, :localizada, :trasladada, :en_albergue, :reunificada],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:localizada, :trasladada, :reunificada],
    reunificada: []
  }


  @doc "Lista de estados válidos."
  @spec estados() :: [estado()]
  def estados, do: @estados

  @doc "Indica si un átomo es un estado válido."
  @spec estado_valido?(term()) :: boolean()
  def estado_valido?(estado) when estado in @estados, do: true
  def estado_valido?(_), do: false

  @doc """
  Convierte un átomo o un texto del usuario (`"en albergue"`, `"Localizada"`,
  `"sin información"`) en un estado válido, sin crear átomos nuevos.
  """
  @spec estado_desde_texto(term()) :: {:ok, estado()} | {:error, :estado_invalido}
  def estado_desde_texto(estado) when is_atom(estado) do
    if estado_valido?(estado), do: {:ok, estado}, else: {:error, :estado_invalido}
  end

  def estado_desde_texto(texto) when is_binary(texto) do
    normalizado = texto |> normalizar() |> String.replace(~r/[\s-]+/, "_")

    case Enum.find(@estados, &(Atom.to_string(&1) == normalizado)) do
      nil -> {:error, :estado_invalido}
      estado -> {:ok, estado}
    end
  end

  def estado_desde_texto(_), do: {:error, :estado_invalido}


  @doc """
  Crea una persona. La edad puede ser `nil` (desconocida). El estado inicial por defecto
  es `:reportada`; también puede indicarse (átomo o texto).
  """
  @spec nuevo(term(), term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def nuevo(id, documento, nombre, edad, zona, estado \\ :reportada) do
    id = limpiar(id)
    documento = limpiar(documento)
    nombre = limpiar(nombre)
    zona = limpiar(zona)

    cond do
      not (texto_valido?(id) and texto_valido?(nombre) and texto_valido?(zona)) ->
        {:error, :datos_invalidos}

      not documento_valido?(documento) ->
        {:error, :documento_invalido}

      not edad_valida?(edad) ->
        {:error, :edad_invalida}

      true ->
        with {:ok, estado} <- estado_desde_texto(estado) do
          {:ok,
           %__MODULE__{
             id: id,
             documento: documento,
             nombre: nombre,
             edad: edad,
             zona: zona,
             estado: estado
           }}
        end
    end
  end

  @doc """
  Cambia el estado de la persona y registra `{fecha, estado_anterior, estado_nuevo}`
  al final del historial.

  Errores: `:estado_invalido`, `:fecha_invalida`, `:transicion_invalida`.
  """
  @spec transicion(t(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def transicion(%__MODULE__{} = persona, nuevo_estado, fecha) do
    with {:ok, destino} <- estado_desde_texto(nuevo_estado),
         :ok <- validar_fecha(fecha),
         :ok <- validar_transicion(persona.estado, destino) do
      registro = {fecha, persona.estado, destino}
      {:ok, %{persona | estado: destino, historial: persona.historial ++ [registro]}}
    end
  end

  @doc """
  Recorre recursivamente la lista y devuelve las personas que cumplen TODOS los filtros.

  """
  @spec buscar([t()], keyword() | map(), [t()]) :: [t()]
  def buscar(personas, filtros, acumulado \\ [])

  def buscar([], _filtros, acumulado), do: Enum.reverse(acumulado)

  def buscar([persona | resto], filtros, acumulado) do
    if coincide?(persona, filtros) do
      buscar(resto, filtros, [persona | acumulado])
    else
      buscar(resto, filtros, acumulado)
    end
  end


  @doc "Convierte la persona a una línea de texto."
  @spec a_linea(t()) :: String.t()
  def a_linea(%__MODULE__{} = p) do
    historial = Enum.map_join(p.historial, ";", fn {fecha, de, a} -> "#{fecha}>#{de}>#{a}" end)

    Persistencia.unir_campos([p.id, p.documento, p.nombre, p.edad, p.zona, p.estado, historial])
  end

  @doc "Reconstruye una persona desde una línea. Devuelve `{:error, :linea_invalida}` si está dañada."
  @spec desde_linea(String.t()) :: {:ok, t()} | {:error, :linea_invalida}
  def desde_linea(linea) when is_binary(linea) do
    with [id, documento, nombre, edad, zona, estado, historial] <-
           linea |> String.trim() |> Persistencia.separar_campos(),
         {:ok, edad} <- leer_edad(edad),
         {:ok, persona} <- nuevo(id, documento, nombre, edad, zona, estado),
         {:ok, historial} <- leer_historial(historial) do
      {:ok, %{persona | historial: historial}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp validar_transicion(estado_actual, destino) do
    if destino in Map.get(@transiciones, estado_actual, []) do
      :ok
    else
      {:error, :transicion_invalida}
    end
  end

  defp validar_fecha(fecha) when is_binary(fecha) do
    if Regex.match?(~r/^[^|;>\r\n]+$/, fecha), do: :ok, else: {:error, :fecha_invalida}
  end

  defp validar_fecha(_), do: {:error, :fecha_invalida}

  defp coincide?(persona, filtros), do: Enum.all?(filtros, &cumple?(persona, &1))

  defp cumple?(_persona, {_clave, nil}), do: true

  defp cumple?(persona, {:nombre, valor}) when is_binary(valor) do
    String.contains?(normalizar(persona.nombre), normalizar(valor))
  end

  defp cumple?(persona, {:documento, valor}) when is_binary(valor) do
    normalizar(persona.documento) == normalizar(valor)
  end

  defp cumple?(persona, {:zona, valor}) when is_binary(valor) do
    normalizar(persona.zona) == normalizar(valor)
  end

  defp cumple?(persona, {:estado, valor}), do: estado_desde_texto(valor) == {:ok, persona.estado}

  defp cumple?(_persona, _otro), do: true

  defp leer_edad(""), do: {:ok, nil}

  defp leer_edad(texto) do
    case Integer.parse(texto) do
      {edad, ""} -> {:ok, edad}
      _ -> :error
    end
  end

  defp leer_historial(""), do: {:ok, []}

  defp leer_historial(texto) do
    texto
    |> String.split(";", trim: true)
    |> Enum.reduce_while({:ok, []}, fn registro, {:ok, acumulado} ->
      with [fecha, de, a] <- String.split(registro, ">"),
           :ok <- validar_fecha(fecha),
           {:ok, de} <- estado_desde_texto(de),
           {:ok, a} <- estado_desde_texto(a) do
        {:cont, {:ok, [{fecha, de, a} | acumulado]}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, registros} -> {:ok, Enum.reverse(registros)}
      :error -> :error
    end
  end

  defp edad_valida?(nil), do: true
  defp edad_valida?(edad), do: is_integer(edad) and edad >= 0 and edad <= 130

  defp limpiar(valor) when is_binary(valor), do: String.trim(valor)
  defp limpiar(_), do: nil

  # Texto libre: no vacío y sin saltos de línea (el `|` se escapa al guardar).
  defp texto_valido?(valor) when is_binary(valor), do: Regex.match?(~r/^[^\r\n]+$/, valor)
  defp texto_valido?(_), do: false

  defp documento_valido?(valor) when is_binary(valor), do: Regex.match?(~r/^[^|,;>\r\n]+$/, valor)
  defp documento_valido?(_), do: false

  # Minúsculas y sin tildes, para comparar textos del usuario.
  defp normalizar(texto) do
    texto
    |> String.downcase()
    |> String.trim()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
