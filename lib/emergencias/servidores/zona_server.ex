defmodule Emergencias.Servidores.ZonaServer do
  @moduledoc """
  Administra los árboles de zonas y guarda cada zona raíz en una línea de zonas.txt.
  """

  use GenServer

  alias Emergencias.Dominio.Zona
  alias Emergencias.Persistencia

  @archivo "zonas.txt"

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def registrar_zona(codigo, nombre, nivel, personas \\ 0) do
    GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel, personas})
  end

  def registrar_sector(padre, codigo, nombre, nivel \\ nil, personas \\ 0) do
    GenServer.call(
      __MODULE__,
      {:registrar_hijo, "sector", padre, codigo, nombre, nivel, personas}
    )
  end

  def registrar_punto(padre, codigo, nombre, nivel \\ nil, personas \\ 0) do
    GenServer.call(__MODULE__, {:registrar_hijo, "punto", padre, codigo, nombre, nivel, personas})
  end

  @doc "Indica si el código corresponde a un nodo registrado."
  def existe?(codigo), do: match?({:ok, _}, obtener(codigo))

  @doc "Obtiene una zona, sector o punto por su código."
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})

  @doc "Lista las zonas raíz con sus respectivos sectores y puntos."
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc "Consulta los datos del nodo, sus hijos directos y los totales de su árbol."
  def estado_zona(codigo) do
    with {:ok, nodo} <- obtener(codigo) do
      datos = %{
        codigo: nodo.codigo,
        nombre: nodo.nombre,
        tipo: nodo.tipo,
        nivel: nodo.nivel,
        hijos: Enum.map(nodo.hijos, & &1.codigo)
      }

      {:ok, Map.merge(datos, Zona.estadisticas(nodo))}
    end
  end

  def estadisticas(codigo) do
    with {:ok, nodo} <- obtener(codigo), do: {:ok, Zona.estadisticas(nodo)}
  end

  @doc "Devuelve los totales de todas las zonas para el resumen global."
  def resumen, do: GenServer.call(__MODULE__, :resumen)

  @impl true
  def init(:ok) do
    case Persistencia.cargar(@archivo, &Zona.desde_linea/1) do
      {:ok, zonas} -> {:ok, Map.new(zonas, &{&1.codigo, &1})}
      {:error, motivo} -> {:stop, motivo}
    end
  end

  @impl true
  def handle_call({:registrar_zona, codigo, nombre, nivel, personas}, _from, zonas) do
    with {:ok, zona} <- Zona.nuevo(codigo, nombre, "zona", nivel, personas),
         :ok <- validar_codigo(zonas, zona.codigo) do
      guardar(zonas, zona, zona)
    else
      error -> {:reply, error, zonas}
    end
  end

  def handle_call({:registrar_hijo, tipo, padre, codigo, nombre, nivel, personas}, _from, zonas) do
    with {:ok, raiz, nodo_padre} <- buscar(zonas, padre),
         nivel = if(is_nil(nivel), do: nodo_padre.nivel, else: nivel),
         {:ok, hijo} <- Zona.nuevo(codigo, nombre, tipo, nivel, personas),
         :ok <- validar_codigo(zonas, hijo.codigo),
         {:ok, raiz_actualizada} <- Zona.agregar_hijo(raiz, padre, hijo) do
      guardar(zonas, raiz_actualizada, hijo)
    else
      error -> {:reply, error, zonas}
    end
  end

  def handle_call({:obtener, codigo}, _from, zonas) do
    resultado =
      case buscar(zonas, codigo) do
        {:ok, _raiz, nodo} -> {:ok, nodo}
        error -> error
      end

    {:reply, resultado, zonas}
  end

  def handle_call(:listar, _from, zonas) do
    {:reply, zonas |> Map.values() |> Enum.sort_by(& &1.codigo), zonas}
  end

  def handle_call(:resumen, _from, zonas) do
    resumen =
      Enum.reduce(
        zonas,
        %{zonas: map_size(zonas), sectores: 0, puntos: 0, personas_afectadas: 0},
        fn
          {_codigo, zona}, total ->
            Map.merge(total, Zona.estadisticas(zona), fn _campo, a, b -> a + b end)
        end
      )

    {:reply, resumen, zonas}
  end

  defp buscar(zonas, codigo) do
    Enum.find_value(zonas, {:error, :no_encontrado}, fn {_codigo, raiz} ->
      case Zona.buscar_nodo(raiz, codigo) do
        {:ok, nodo} -> {:ok, raiz, nodo}
        {:error, :no_encontrado} -> nil
      end
    end)
  end

  defp validar_codigo(zonas, codigo) do
    case buscar(zonas, codigo) do
      {:ok, _, _} -> {:error, :id_duplicado}
      {:error, :no_encontrado} -> :ok
    end
  end

  defp guardar(zonas, raiz, registrado) do
    actualizadas = Map.put(zonas, raiz.codigo, raiz)

    case Persistencia.guardar(@archivo, Map.values(actualizadas), &Zona.a_linea/1) do
      :ok -> {:reply, {:ok, registrado}, actualizadas}
      error -> {:reply, error, zonas}
    end
  end
end
