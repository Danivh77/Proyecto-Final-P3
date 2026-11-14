defmodule Emergencias.Persistencia do
  @moduledoc """
  Guarda y recupera los datos del sistema en archivos de texto plano.
  Cada registro es una línea y sus campos se separan con `|`.
  """

  @separador "|"
  @carpeta_iniciales "datos_iniciales"

  @doc "Carpeta de datos: `data` normalmente y `data_test` en las pruebas."
  def carpeta_datos do
    Application.get_env(:emergencias, :carpeta_datos, "data")
  end

  @doc "Ruta completa de un archivo dentro de la carpeta de datos."
  def ruta(archivo) when is_binary(archivo) do
    Path.join(carpeta_datos(), archivo)
  end

  @doc "Crea la carpeta del archivo si no existe."
  def asegurar_directorio(ruta_archivo) when is_binary(ruta_archivo) do
    ruta_archivo
    |> Path.dirname()
    |> File.mkdir_p()
  end

  @doc "Lee un archivo y convierte cada línea. Si el archivo no existe devuelve `{:ok, []}`."
  def cargar(archivo, convertir) when is_binary(archivo) and is_function(convertir, 1) do
    case File.read(ruta(archivo)) do
      {:ok, contenido} ->
        lineas = String.split(contenido, ["\r\n", "\n"])
        {:ok, parsear_lineas(lineas, convertir)}

      {:error, :enoent} ->
        {:ok, []}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  @doc "Convierte una lista de líneas en valores, ignorando las vacías o dañadas. Recursiva."
  def parsear_lineas(lineas, convertir) when is_list(lineas) and is_function(convertir, 1) do
    parsear_lineas(lineas, convertir, [])
  end

  defp parsear_lineas([], _convertir, acumulado), do: Enum.reverse(acumulado)

  defp parsear_lineas([linea | resto], convertir, acumulado) do
    case String.trim(linea) do
      "" ->
        parsear_lineas(resto, convertir, acumulado)

      limpia ->
        case convertir.(limpia) do
          {:ok, valor} -> parsear_lineas(resto, convertir, [valor | acumulado])
          _ -> parsear_lineas(resto, convertir, acumulado)
        end
    end
  end

  @doc "Reescribe el archivo completo con los elementos dados."
  def guardar(archivo, elementos, convertir)
      when is_binary(archivo) and is_list(elementos) and is_function(convertir, 1) do
    destino = ruta(archivo)
    contenido = Enum.map_join(elementos, fn elemento -> convertir.(elemento) <> "\n" end)

    with :ok <- asegurar_directorio(destino) do
      File.write(destino, contenido)
    end
  end

  @doc "Agrega una línea al final del archivo sin borrar lo anterior."
  def agregar_linea(archivo, linea) when is_binary(archivo) and is_binary(linea) do
    destino = ruta(archivo)

    with :ok <- asegurar_directorio(destino) do
      File.write(destino, linea <> "\n", [:append])
    end
  end

  @doc "Lista los archivos `.txt` de una subcarpeta de datos."
  def listar_archivos(subcarpeta) when is_binary(subcarpeta) do
    case File.ls(ruta(subcarpeta)) do
      {:ok, nombres} ->
        nombres
        |> Enum.filter(&String.ends_with?(&1, ".txt"))
        |> Enum.sort()
        |> Enum.map(&Path.join(subcarpeta, &1))

      {:error, _} ->
        []
    end
  end

  @doc "Une los campos en una línea separada por `|`. `nil` se guarda vacío."
  def unir_campos(campos) when is_list(campos) do
    Enum.map_join(campos, @separador, &escapar/1)
  end

  # Escapa los caracteres que dañarían la línea: \, | y saltos de línea.
  defp escapar(nil), do: ""

  defp escapar(valor) do
    valor
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(@separador, "\\" <> @separador)
    |> String.replace("\n", "\\n")
  end

  @doc "Separa una línea en sus campos respetando los caracteres escapados. Recursiva."
  def separar_campos(linea) when is_binary(linea) do
    separar(String.graphemes(linea), "", [])
  end

  defp separar([], actual, campos), do: Enum.reverse([actual | campos])
  defp separar(["\\", "n" | resto], actual, campos), do: separar(resto, actual <> "\n", campos)
  defp separar(["\\", c | resto], actual, campos), do: separar(resto, actual <> c, campos)
  defp separar([@separador | resto], actual, campos), do: separar(resto, "", [actual | campos])
  defp separar([c | resto], actual, campos), do: separar(resto, actual <> c, campos)

  @doc "Copia `datos_iniciales/` a la carpeta de datos si esta está vacía."
  def cargar_datos_iniciales do
    destino = carpeta_datos()

    cond do
      not File.dir?(@carpeta_iniciales) ->
        {:ok, :sin_datos_iniciales}

      tiene_datos?(destino) ->
        {:ok, :ya_existian}

      true ->
        case File.cp_r(@carpeta_iniciales, destino) do
          {:ok, _} -> {:ok, :copiados}
          {:error, motivo, _} -> {:error, motivo}
        end
    end
  end

  defp tiene_datos?(carpeta) do
    case File.ls(carpeta) do
      {:ok, nombres} -> Enum.any?(nombres, &(&1 != ".gitkeep"))
      {:error, _} -> false
    end
  end
end
