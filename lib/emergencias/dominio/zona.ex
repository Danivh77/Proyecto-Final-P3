defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  Árbol de zonas afectadas. Una zona contiene sectores y cada sector
  contiene puntos de atención.
  """

  alias Emergencias.Persistencia

  @tipos ~w(zona sector punto)
  @niveles ~w(critico crítico alto medio bajo)

  defstruct [:codigo, :nombre, :tipo, :nivel, :personas_afectadas, hijos: []]

  @doc "Guard para validar el nivel de afectación."
  defguard nivel_valido?(nivel) when nivel in @niveles

  @doc "Crea un nodo sin hijos y valida sus datos."
  def nuevo(codigo, nombre, tipo, nivel, personas_afectadas) do
    cond do
      vacio?(codigo) ->
        {:error, :codigo_invalido}

      vacio?(nombre) ->
        {:error, :nombre_invalido}

      tipo not in @tipos ->
        {:error, :tipo_invalido}

      not nivel_valido?(nivel) ->
        {:error, :nivel_invalido}

      not is_integer(personas_afectadas) or personas_afectadas < 0 ->
        {:error, :personas_afectadas_invalidas}

      true ->
        {:ok,
         %__MODULE__{
           codigo: String.trim(codigo),
           nombre: nombre,
           tipo: tipo,
           nivel: nivel,
           personas_afectadas: personas_afectadas
         }}
    end
  end

  @doc "Agrega un hijo al padre indicado y devuelve el árbol actualizado."
  def agregar_hijo(%__MODULE__{} = arbol, codigo_padre, %__MODULE__{} = hijo) do
    codigos = listar_codigos(arbol) ++ listar_codigos(hijo)

    if codigos_unicos?(codigos) do
      insertar(arbol, codigo_padre, hijo)
    else
      {:error, :id_duplicado}
    end
  end

  defp insertar(%__MODULE__{codigo: codigo} = padre, codigo, hijo) do
    if tipo_hijo?(padre.tipo, hijo.tipo) do
      {:ok, %{padre | hijos: padre.hijos ++ [hijo]}}
    else
      {:error, :jerarquia_invalida}
    end
  end

  defp insertar(nodo, codigo_padre, hijo) do
    with {:ok, hijos} <- insertar_en_hijos(nodo.hijos, codigo_padre, hijo) do
      {:ok, %{nodo | hijos: hijos}}
    end
  end

  defp insertar_en_hijos([], _codigo_padre, _hijo), do: {:error, :no_encontrado}

  defp insertar_en_hijos([nodo | resto], codigo_padre, hijo) do
    case insertar(nodo, codigo_padre, hijo) do
      {:ok, actualizado} ->
        {:ok, [actualizado | resto]}

      {:error, :no_encontrado} ->
        with {:ok, resto_actualizado} <- insertar_en_hijos(resto, codigo_padre, hijo) do
          {:ok, [nodo | resto_actualizado]}
        end

      error ->
        error
    end
  end

  @doc "Busca un código en el árbol, empezando por su raíz."
  def buscar_nodo(%__MODULE__{codigo: codigo} = nodo, codigo), do: {:ok, nodo}

  def buscar_nodo(%__MODULE__{hijos: hijos}, codigo) do
    Enum.find_value(hijos, {:error, :no_encontrado}, fn hijo ->
      case buscar_nodo(hijo, codigo) do
        {:ok, _} = resultado -> resultado
        {:error, :no_encontrado} -> nil
      end
    end)
  end

  @doc "Suma personas afectadas y cuenta sectores y puntos de todo el árbol."
  def estadisticas(%__MODULE__{} = nodo) do
    propias = %{
      personas_afectadas: nodo.personas_afectadas,
      sectores: if(nodo.tipo == "sector", do: 1, else: 0),
      puntos: if(nodo.tipo == "punto", do: 1, else: 0)
    }

    Enum.reduce(nodo.hijos, propias, fn hijo, total ->
      Map.merge(total, estadisticas(hijo), fn _campo, a, b -> a + b end)
    end)
  end

  @doc "Lista los códigos en preorden, visitando cada padre antes de sus hijos."
  def listar_codigos(%__MODULE__{} = nodo) do
    [nodo.codigo | Enum.flat_map(nodo.hijos, &listar_codigos/1)]
  end

  @doc "Guarda un árbol en una línea con los campos de cada nodo y su número de hijos."
  def a_linea(%__MODULE__{} = nodo), do: Persistencia.unir_campos(campos(nodo))

  defp campos(nodo) do
    [
      nodo.codigo,
      nodo.nombre,
      nodo.tipo,
      nodo.nivel,
      nodo.personas_afectadas,
      length(nodo.hijos)
      | Enum.flat_map(nodo.hijos, &campos/1)
    ]
  end

  @doc "Recupera un árbol completo o devuelve un error si la línea está dañada."
  def desde_linea(linea) when is_binary(linea) do
    with {:ok, nodo, []} <- leer_nodo(Persistencia.separar_campos(linea)),
         true <- codigos_unicos?(listar_codigos(nodo)) do
      {:ok, nodo}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp leer_nodo([codigo, nombre, tipo, nivel, personas, cantidad_hijos | resto]) do
    with {personas, ""} <- Integer.parse(personas),
         {cantidad, ""} when cantidad >= 0 <- Integer.parse(cantidad_hijos),
         {:ok, nodo} <- nuevo(codigo, nombre, tipo, nivel, personas),
         {:ok, hijos, resto} <- leer_hijos(resto, tipo, cantidad, []) do
      {:ok, %{nodo | hijos: hijos}, resto}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  defp leer_nodo(_), do: {:error, :linea_invalida}

  defp leer_hijos(campos, _tipo, 0, hijos), do: {:ok, Enum.reverse(hijos), campos}

  defp leer_hijos(campos, tipo, cantidad, hijos) do
    with {:ok, hijo, resto} <- leer_nodo(campos),
         true <- tipo_hijo?(tipo, hijo.tipo) do
      leer_hijos(resto, tipo, cantidad - 1, [hijo | hijos])
    else
      _ -> {:error, :linea_invalida}
    end
  end

  defp tipo_hijo?("zona", "sector"), do: true
  defp tipo_hijo?("sector", "punto"), do: true
  defp tipo_hijo?(_, _), do: false

  defp codigos_unicos?(codigos), do: MapSet.size(MapSet.new(codigos)) == length(codigos)

  defp vacio?(texto) when is_binary(texto), do: String.trim(texto) == ""
  defp vacio?(_), do: true
end
