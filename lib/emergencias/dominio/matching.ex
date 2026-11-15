defmodule Emergencias.Dominio.Matching do
  @moduledoc """
  Algoritmo de coincidencia entre reportes de mascotas perdidas y encontradas.

  """

  alias Emergencias.Dominio.ReporteMascota

  @umbral 60
  @puntos_zona 30
  @puntos_color 25
  @puntos_tamano 20
  @puntos_por_palabra 5
  @maximo_caracteristicas 25

  # Palabras sin valor para comparar características.
  @ignoradas ~w(con sin las los una uno que del por para muy tiene)

  @doc "Puntaje mínimo para considerar una posible coincidencia."
  @spec umbral() :: non_neg_integer()
  def umbral, do: @umbral

  @doc "Puntaje de similitud entre dos reportes."
  @spec puntaje(ReporteMascota.t(), ReporteMascota.t()) :: non_neg_integer()
  def puntaje(%ReporteMascota{} = a, %ReporteMascota{} = b) do
    if igual?(a.especie, b.especie) do
      puntos_si(igual?(a.zona, b.zona), @puntos_zona) +
        puntos_si(igual?(a.color, b.color), @puntos_color) +
        puntos_si(igual?(a.tamano, b.tamano), @puntos_tamano) +
        min(
          length(palabras_comunes(a.caracteristicas, b.caracteristicas)) * @puntos_por_palabra,
          @maximo_caracteristicas
        )
    else
      0
    end
  end

  @doc "Palabras significativas que aparecen en ambas descripciones."
  @spec palabras_comunes(String.t() | nil, String.t() | nil) :: [String.t()]
  def palabras_comunes(texto_a, texto_b) do
    texto_a |> palabras() |> MapSet.intersection(palabras(texto_b)) |> Enum.sort()
  end

  @doc """
  Reportes que pueden coincidir con `reporte`: de tipo contrario, misma especie,
  distintos de él y todavía abiertos.
  """
  @spec candidatos(ReporteMascota.t(), [ReporteMascota.t()]) :: [ReporteMascota.t()]
  def candidatos(%ReporteMascota{} = reporte, reportes) do
    Enum.filter(reportes, fn otro ->
      otro.id != reporte.id and
        otro.tipo != reporte.tipo and
        otro.estado in [:activa, :posible_coincidencia] and
        igual?(otro.especie, reporte.especie)
    end)
  end

  @doc """
  Recorre recursivamente los candidatos acumulando el de mayor puntaje.

  El tercer argumento es el acumulado.
  """
  @spec mejor_coincidencia(
          ReporteMascota.t(),
          [ReporteMascota.t()],
          nil | {ReporteMascota.t(), integer()}
        ) ::
          {:ok, {ReporteMascota.t(), non_neg_integer()}} | {:error, :sin_coincidencia}
  def mejor_coincidencia(reporte, candidatos, acumulado \\ nil)

  def mejor_coincidencia(_reporte, [], {candidato, puntos}) when puntos >= @umbral do
    {:ok, {candidato, puntos}}
  end

  def mejor_coincidencia(_reporte, [], _acumulado), do: {:error, :sin_coincidencia}

  def mejor_coincidencia(reporte, [candidato | resto], acumulado) do
    puntos = puntaje(reporte, candidato)

    nuevo_acumulado =
      case acumulado do
        {_mejor, mejores_puntos} when mejores_puntos >= puntos -> acumulado
        _ -> {candidato, puntos}
      end

    mejor_coincidencia(reporte, resto, nuevo_acumulado)
  end


  defp igual?(a, b), do: ReporteMascota.normalizar(a) == ReporteMascota.normalizar(b)

  defp puntos_si(true, puntos), do: puntos
  defp puntos_si(false, _puntos), do: 0

  defp palabras(nil), do: MapSet.new()

  defp palabras(texto) do
    texto
    |> ReporteMascota.normalizar()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3 or &1 in @ignoradas))
    |> MapSet.new()
  end
end
