defmodule Emergencias.Servidores.MascotaServer do
  @moduledoc """
  Guarda los reportes de mascotas perdidas y encontradas y calcula las coincidencias.

  """

  use GenServer

  alias Emergencias.Dominio.{Matching, ReporteMascota}
  alias Emergencias.Persistencia
  alias Emergencias.Util.Ids

  @archivo "mascotas.txt"
  @tiempo_calculo 5_000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra un reporte. `tipo` es `:perdida`/`:encontrada` (o `"lost"`/`"found"`).
  `datos` es un mapa o keyword con `:especie`, `:nombre`, `:caracteristicas`, `:color`,
  `:tamano`, `:zona` y `:contacto`. Devuelve `{:ok, reporte}` o `{:error, motivo}`.
  """
  def reportar(tipo, datos) do
    if is_map(datos) or Keyword.keyword?(datos) do
      GenServer.call(__MODULE__, {:reportar, tipo, Map.new(datos)})
    else
      {:error, :datos_invalidos}
    end
  end

  @doc """
  Lista los reportes (ordenados por id). Filtros: `:especie`, `:zona`, `:estado`, `:tipo`
  (keyword o mapa). Devuelve `{:ok, lista}`.
  """
  def listar(filtros \\ []) do
    if is_list(filtros) or is_map(filtros) do
      GenServer.call(__MODULE__, {:listar, filtros})
    else
      {:error, :filtros_invalidos}
    end
  end

  @doc """
  Recalcula las posibles coincidencias entre reportes abiertos y marca ambos lados como
  `:posible_coincidencia`.
  """
  def buscar_coincidencias, do: GenServer.call(__MODULE__, :buscar_coincidencias, 15_000)

  @doc """
  Confirma que dos reportes (uno perdido y otro encontrado, de la misma especie) son la
  misma mascota y cierra ambos.
  """
  def confirmar_coincidencia(id_a, id_b) do
    GenServer.call(__MODULE__, {:confirmar_coincidencia, id_a, id_b})
  end

  @doc "Totales para el comando summary."
  def resumen, do: GenServer.call(__MODULE__, :resumen)


  @impl true
  def init(:ok) do
    {:ok, lista} = Persistencia.cargar(@archivo, &ReporteMascota.desde_linea/1)
    {:ok, %{reportes: Map.new(lista, fn r -> {r.id, r} end)}}
  end

  @impl true
  def handle_call({:reportar, tipo, datos}, _from, estado) do
    id = Ids.siguiente("M", Map.keys(estado.reportes))

    with {:ok, reporte} <-
           ReporteMascota.nuevo(
             id,
             tipo,
             datos[:especie],
             datos[:nombre],
             datos[:caracteristicas],
             datos[:color],
             datos[:tamano],
             datos[:zona],
             datos[:contacto]
           ),
         reportes = Map.put(estado.reportes, id, reporte),
         :ok <- guardar(reportes) do
      {:reply, {:ok, reporte}, %{estado | reportes: reportes}}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:listar, filtros}, _from, estado) do
    lista = estado.reportes |> ordenados() |> ReporteMascota.filtrar(filtros)
    {:reply, {:ok, lista}, estado}
  end

  def handle_call(:buscar_coincidencias, _from, estado) do
    # Se parte de cero: las posibles coincidencias anteriores se vuelven a calcular.
    base = Map.new(estado.reportes, fn {id, r} -> {id, reiniciar_posible(r)} end)
    pares = base |> ordenados() |> calcular_pares()

    with {:ok, reportes} <- aplicar_pares(base, pares),
         :ok <- guardar(reportes) do
      {:reply, {:ok, describir_pares(pares, reportes)}, %{estado | reportes: reportes}}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:confirmar_coincidencia, id_a, id_b}, _from, estado) do
    with {:ok, a} <- obtener(estado.reportes, id_a),
         {:ok, b} <- obtener(estado.reportes, id_b),
         :ok <- validar_par(a, b),
         {:ok, a_resuelto} <- ReporteMascota.resolver(a, b.id),
         {:ok, b_resuelto} <- ReporteMascota.resolver(b, a.id),
         reportes = estado.reportes |> Map.put(a.id, a_resuelto) |> Map.put(b.id, b_resuelto),
         :ok <- guardar(reportes) do
      {:reply, {:ok, [a_resuelto, b_resuelto]}, %{estado | reportes: reportes}}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call(:resumen, _from, estado) do
    lista = Map.values(estado.reportes)
    abiertos = fn tipo -> Enum.count(lista, &(&1.tipo == tipo and &1.estado != :resuelta)) end

    resumen = %{
      mascotas_reportadas: length(lista),
      mascotas_perdidas_abiertas: abiertos.(:perdida),
      mascotas_encontradas_abiertas: abiertos.(:encontrada),
      mascotas_posibles_coincidencias: Enum.count(lista, &(&1.estado == :posible_coincidencia)),
      mascotas_resueltas: Enum.count(lista, &(&1.estado == :resuelta))
    }

    {:reply, resumen, estado}
  end


  defp ordenados(reportes), do: reportes |> Map.values() |> Enum.sort_by(& &1.id)

  defp guardar(reportes) do
    Persistencia.guardar(@archivo, ordenados(reportes), &ReporteMascota.a_linea/1)
  end

  defp obtener(reportes, id) do
    id = if is_binary(id), do: id |> String.trim() |> String.upcase(), else: nil

    case Map.fetch(reportes, id) do
      {:ok, reporte} -> {:ok, reporte}
      :error -> {:error, :reporte_no_encontrado}
    end
  end

  defp reiniciar_posible(%ReporteMascota{estado: :posible_coincidencia} = reporte) do
    %{reporte | estado: :activa, coincidencia_con: nil}
  end

  defp reiniciar_posible(reporte), do: reporte

  defp validar_par(%{id: id}, %{id: id}), do: {:error, :mismo_reporte}
  defp validar_par(%{tipo: tipo}, %{tipo: tipo}), do: {:error, :tipos_incompatibles}

  defp validar_par(a, b) do
    if ReporteMascota.normalizar(a.especie) == ReporteMascota.normalizar(b.especie) do
      :ok
    else
      {:error, :especies_distintas}
    end
  end

  # Para cada perdida abierta busca en paralelo su mejor candidata; luego reparte las
  # parejas de mayor a menor puntaje sin repetir ninguna encontrada.
  defp calcular_pares(reportes) do
    reportes
    |> Enum.filter(&(&1.tipo == :perdida and &1.estado == :activa))
    |> Task.async_stream(
      fn perdida ->
        candidatos = Matching.candidatos(perdida, reportes)
        {perdida.id, Matching.mejor_coincidencia(perdida, candidatos)}
      end,
      timeout: @tiempo_calculo
    )
    |> Enum.flat_map(fn
      {:ok, {id_perdida, {:ok, {encontrada, puntaje}}}} -> [{id_perdida, encontrada.id, puntaje}]
      _ -> []
    end)
    |> Enum.sort_by(fn {perdida, encontrada, puntaje} -> {-puntaje, perdida, encontrada} end)
    |> repartir_sin_repetir()
  end

  defp repartir_sin_repetir(pares) do
    {elegidos, _usadas} =
      Enum.reduce(pares, {[], MapSet.new()}, fn {_p, encontrada, _pts} = par, {acc, usadas} ->
        if MapSet.member?(usadas, encontrada) do
          {acc, usadas}
        else
          {[par | acc], MapSet.put(usadas, encontrada)}
        end
      end)

    Enum.reverse(elegidos)
  end

  # Marca ambos reportes de cada pareja como posible coincidencia. Recursiva.
  defp aplicar_pares(reportes, []), do: {:ok, reportes}

  defp aplicar_pares(reportes, [{id_perdida, id_encontrada, _puntaje} | resto]) do
    with {:ok, perdida} <- ReporteMascota.marcar_posible(reportes[id_perdida], id_encontrada),
         {:ok, encontrada} <- ReporteMascota.marcar_posible(reportes[id_encontrada], id_perdida) do
      reportes
      |> Map.put(id_perdida, perdida)
      |> Map.put(id_encontrada, encontrada)
      |> aplicar_pares(resto)
    end
  end

  defp describir_pares(pares, reportes) do
    Enum.map(pares, fn {id_perdida, id_encontrada, puntaje} ->
      %{
        perdida: id_perdida,
        encontrada: id_encontrada,
        puntaje: puntaje,
        especie: reportes[id_perdida].especie
      }
    end)
  end
end
