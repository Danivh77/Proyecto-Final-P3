defmodule Emergencias.Servidores.AlbergueSupervisor do
  @moduledoc """
  DynamicSupervisor que crea un proceso `AlbergueServer` por cada albergue.

  """

  use DynamicSupervisor

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.AlbergueServer

  def start_link(_opts \\ []) do
    with {:ok, pid} <- DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__) do
      cargar_existentes()
      {:ok, pid}
    end
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Crea un albergue y su proceso.
  """
  def crear_albergue(codigo, nombre, zona, capacidad) do
    with {:ok, albergue} <- Albergue.nuevo(codigo, nombre, zona, capacidad),
         :ok <- verificar_codigo_libre(albergue.codigo) do
      case DynamicSupervisor.start_child(__MODULE__, {AlbergueServer, albergue}) do
        {:ok, _pid} -> {:ok, albergue}
        {:error, {:already_started, _pid}} -> {:error, :albergue_ya_existe}
        {:error, motivo} -> {:error, motivo}
      end
    end
  end

  @doc """
  Levanta un proceso por cada archivo de `albergues/` (los dañados se ignoran).

  """
  def cargar_existentes do
    iniciados =
      "albergues"
      |> Persistencia.listar_archivos()
      |> Enum.count(&iniciar_desde_archivo/1)

    {:ok, iniciados}
  end

  @doc "Todos los albergues como mapas (código, nombre, zona, capacidad, ocupación, cupos, %)."
  def listar do
    {:ok, Enum.map(todos(), &AlbergueServer.resumen_albergue/1)}
  end

  @doc "Cupos libres de cada albergue: `{:ok, [%{codigo:, nombre:, zona:, cupos:}]}`."
  def cupos_disponibles do
    lista =
      Enum.map(todos(), fn albergue ->
        %{
          codigo: albergue.codigo,
          nombre: albergue.nombre,
          zona: albergue.zona,
          cupos: Albergue.cupos(albergue)
        }
      end)

    {:ok, lista}
  end

  @doc """
  Reporte de los albergues con mayor ocupación (por porcentaje; si empatan, por número
  de ocupantes). `limite` es cuántos mostrar (5 por defecto).
  """
  def mas_ocupados(limite \\ 5)

  def mas_ocupados(limite) when is_integer(limite) and limite > 0 do
    lista =
      todos()
      |> Enum.map(&AlbergueServer.resumen_albergue/1)
      |> Enum.sort_by(&{-&1.porcentaje, -&1.ocupacion, &1.codigo})
      |> Enum.take(limite)

    {:ok, lista}
  end

  def mas_ocupados(_limite), do: {:error, :limite_invalido}

  @doc "Totales para el comando summary."
  def resumen do
    albergues = todos()

    %{
      albergues_registrados: length(albergues),
      albergues_capacidad_total: albergues |> Enum.map(& &1.capacidad) |> Enum.sum(),
      albergues_ocupacion_total: albergues |> Enum.map(&Albergue.ocupacion/1) |> Enum.sum(),
      albergues_cupos_libres: albergues |> Enum.map(&Albergue.cupos/1) |> Enum.sum()
    }
  end

  defp verificar_codigo_libre(codigo) do
    en_ejecucion = Registry.lookup(Emergencias.Registry, {:albergue, codigo}) != []
    con_archivo = File.exists?(Persistencia.ruta("albergues/#{codigo}.txt"))

    if en_ejecucion or con_archivo, do: {:error, :albergue_ya_existe}, else: :ok
  end

  defp iniciar_desde_archivo(archivo) do
    with {:ok, [albergue | _]} <- Persistencia.cargar(archivo, &Albergue.desde_linea/1),
         {:ok, _pid} <- DynamicSupervisor.start_child(__MODULE__, {AlbergueServer, albergue}) do
      true
    else
      _ -> false
    end
  end

  # Los albergues que están funcionando, ordenados por código.
  defp todos do
    Emergencias.Registry
    |> Registry.select([{{{:albergue, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
    |> Enum.flat_map(fn codigo ->
      case AlbergueServer.obtener(codigo) do
        {:ok, albergue} -> [albergue]
        _ -> []
      end
    end)
  end
end
