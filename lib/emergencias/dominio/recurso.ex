defmodule Emergencias.Dominio.Recurso do
  @moduledoc "Recurso disponible en una ubicación y operaciones puras sobre su inventario."

  alias Emergencias.Persistencia

  defstruct [:codigo, :nombre, :categoria, :cantidad, :unidad, :ubicacion]

  @doc "Crea un recurso con una cantidad inicial entera mayor o igual a cero."
  def nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    cond do
      vacio?(codigo) ->
        {:error, :codigo_invalido}

      vacio?(nombre) ->
        {:error, :nombre_invalido}

      vacio?(categoria) ->
        {:error, :categoria_invalida}

      not is_integer(cantidad) or cantidad < 0 ->
        {:error, :cantidad_invalida}

      vacio?(unidad) ->
        {:error, :unidad_invalida}

      vacio?(ubicacion) ->
        {:error, :ubicacion_invalida}

      true ->
        {:ok,
         %__MODULE__{
           codigo: String.trim(codigo),
           nombre: nombre,
           categoria: categoria,
           cantidad: cantidad,
           unidad: unidad,
           ubicacion: ubicacion
         }}
    end
  end

  @doc "Devuelve el recurso con la cantidad sumada."
  def entrada(%__MODULE__{} = recurso, cantidad) when is_integer(cantidad) and cantidad > 0 do
    {:ok, %{recurso | cantidad: recurso.cantidad + cantidad}}
  end

  def entrada(%__MODULE__{}, _cantidad), do: {:error, :cantidad_invalida}

  @doc "Descuenta una cantidad positiva cuando hay suficiente inventario."
  def salida(%__MODULE__{} = recurso, cantidad) when is_integer(cantidad) and cantidad > 0 do
    if puede_cubrir?(recurso, cantidad) do
      {:ok, %{recurso | cantidad: recurso.cantidad - cantidad}}
    else
      {:error, :inventario_insuficiente}
    end
  end

  def salida(%__MODULE__{}, _cantidad), do: {:error, :cantidad_invalida}

  @doc "Indica si el recurso puede cubrir una solicitud de cantidad positiva."
  def puede_cubrir?(%__MODULE__{cantidad: disponible}, cantidad) do
    is_integer(cantidad) and cantidad > 0 and cantidad <= disponible
  end

  @doc "Convierte el recurso en una línea de texto."
  def a_linea(%__MODULE__{} = recurso) do
    Persistencia.unir_campos([
      recurso.codigo,
      recurso.nombre,
      recurso.categoria,
      recurso.cantidad,
      recurso.unidad,
      recurso.ubicacion
    ])
  end

  @doc "Recupera un recurso desde una línea y valida sus campos."
  def desde_linea(linea) when is_binary(linea) do
    with [codigo, nombre, categoria, texto, unidad, ubicacion] <-
           Persistencia.separar_campos(linea),
         {cantidad, ""} <- Integer.parse(texto),
         {:ok, recurso} <- nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion) do
      {:ok, recurso}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def desde_linea(_), do: {:error, :linea_invalida}

  defp vacio?(texto) when is_binary(texto), do: String.trim(texto) == ""
  defp vacio?(_), do: true
end
