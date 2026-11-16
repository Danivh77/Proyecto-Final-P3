defmodule Emergencias.Servidores.AlbergueServer do

  use GenServer

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.{FamiliaServer, InventarioServer, NecesidadServer}

  @doc "Inicia el proceso de un albergue (lo llama el `AlbergueSupervisor`)."
  def start_link(%Albergue{} = albergue) do
    GenServer.start_link(__MODULE__, albergue, name: via(albergue.codigo))
  end

  @doc "Nombre del proceso del albergue en el `Registry`."
  def via(codigo), do: {:via, Registry, {Emergencias.Registry, {:albergue, codigo}}}

  @doc "Devuelve el struct `Albergue` actual: `{:ok, albergue}` o `{:error, :albergue_no_encontrado}`."
  def obtener(codigo), do: llamar(codigo, :obtener)

  @doc """
  Información del albergue: capacidad, ocupación, cupos, porcentaje, ocupantes y los
  recursos y necesidades asociados.
  """
  def consultar(codigo) do
    with {:ok, albergue} <- obtener(codigo) do
      recursos = Enum.map(InventarioServer.por_ubicacion(albergue.codigo), & &1.codigo)
      necesidades = Enum.map(NecesidadServer.por_albergue(albergue.codigo), & &1.id)

      informacion =
        Map.merge(resumen_albergue(albergue), %{
          ocupantes: albergue.ocupantes |> MapSet.to_list() |> Enum.sort(),
          recursos: Enum.uniq(albergue.recursos ++ recursos),
          necesidades: Enum.uniq(albergue.necesidades ++ necesidades)
        })
      {:ok, informacion}
    end
  end

  @doc """
  Registra el ingreso de una persona. Si la persona está registrada en `FamiliaServer`
  también pasa a `:en_albergue`.
  """
  def registrar_entrada(codigo, documento), do: llamar(codigo, {:entrada, documento})

  @doc "Registra la salida de una persona."
  def registrar_salida(codigo, documento), do: llamar(codigo, {:salida, documento})

  @doc "Asocia el código de un recurso al albergue."
  def asociar_recurso(codigo, codigo_recurso),
    do: llamar(codigo, {:asociar_recurso, codigo_recurso})

  @doc "Asocia el id de una necesidad al albergue."
  def asociar_necesidad(codigo, id_necesidad),
    do: llamar(codigo, {:asociar_necesidad, id_necesidad})

  @doc "Datos básicos de un albergue como mapa (para tablas y reportes)."
  def resumen_albergue(%Albergue{} = albergue) do
    %{
      codigo: albergue.codigo,
      nombre: albergue.nombre,
      zona: albergue.zona,
      capacidad: albergue.capacidad,
      ocupacion: Albergue.ocupacion(albergue),
      cupos: Albergue.cupos(albergue),
      porcentaje: Albergue.porcentaje_ocupacion(albergue)
    }
  end


  # Si ya existe el archivo del albergue (arranque o reinicio tras un fallo) se carga el
  # último estado guardado; si no, se guarda el albergue recién creado.
  @impl true
  def init(%Albergue{} = inicial) do
    archivo = archivo(inicial.codigo)

    case Persistencia.cargar(archivo, &Albergue.desde_linea/1) do
      {:ok, [guardado | _]} ->
        {:ok, guardado}

      {:ok, []} ->
        case guardar(inicial) do
          :ok -> {:ok, inicial}
          {:error, motivo} -> {:stop, motivo}
        end

      {:error, motivo} ->
        {:stop, motivo}
    end
  end

  @impl true
  def handle_call(:obtener, _from, albergue), do: {:reply, {:ok, albergue}, albergue}

  def handle_call({:entrada, documento}, _from, albergue) do

    with {:ok, nuevo} <- Albergue.ingresar(albergue, documento),
         :ok <- pasar_a_en_albergue(String.trim(documento)),
         :ok <- guardar(nuevo) do
      {:reply, {:ok, nuevo}, nuevo}
    else
      error -> {:reply, error, albergue}
    end
  end

  def handle_call({:salida, documento}, _from, albergue) do
    with {:ok, nuevo} <- Albergue.salir(albergue, documento),
         :ok <- guardar(nuevo) do
      {:reply, {:ok, nuevo}, nuevo}
    else
      error -> {:reply, error, albergue}
    end
  end

  def handle_call({:asociar_recurso, codigo_recurso}, _from, albergue) do
    con_guardado(albergue, Albergue.asociar_recurso(albergue, codigo_recurso))
  end

  def handle_call({:asociar_necesidad, id_necesidad}, _from, albergue) do
    con_guardado(albergue, Albergue.asociar_necesidad(albergue, id_necesidad))
  end


  # Responde al cliente. Si el resultado es un nuevo albergue lo guarda antes de
  # adoptarlo; si algo falla, el estado no cambia.
  defp con_guardado(albergue, {:ok, nuevo}) do
    case guardar(nuevo) do
      :ok -> {:reply, {:ok, nuevo}, nuevo}
      error -> {:reply, error, albergue}
    end
  end

  defp con_guardado(albergue, error), do: {:reply, error, albergue}

  defp pasar_a_en_albergue(documento) do
    case FamiliaServer.cambiar_estado(documento, :en_albergue) do
      {:ok, _persona} -> :ok
      {:error, :persona_no_encontrada} -> :ok
      error -> error
    end
  end

  defp llamar(codigo, mensaje) do
    case Albergue.normalizar_codigo(codigo) do
      nil -> {:error, :albergue_no_encontrado}
      codigo_normalizado -> GenServer.call(via(codigo_normalizado), mensaje)
    end
  catch
    :exit, {:noproc, _} -> {:error, :albergue_no_encontrado}
  end

  defp archivo(codigo), do: "albergues/#{codigo}.txt"

  defp guardar(%Albergue{} = albergue) do
    Persistencia.guardar(archivo(albergue.codigo), [albergue], &Albergue.a_linea/1)
  end
end
