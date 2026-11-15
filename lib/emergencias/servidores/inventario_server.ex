defmodule Emergencias.Servidores.InventarioServer do
  @moduledoc """
  Administra las existencias por código y ubicación. Cada operación de escritura
  valida y cambia el inventario en una sola llamada al servidor.
  """

  use GenServer
  require Logger

  alias Emergencias.Dominio.{Movimiento, Recurso, Zona}
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.ZonaServer

  @recursos "recursos.txt"
  @movimientos "movimientos.txt"
  @pendiente ".inventario_pendiente.txt"
  @umbral 10

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    llamar({:registrar, codigo, nombre, categoria, cantidad, unidad, ubicacion})
  end

  def entrada(recurso, cantidad, usuario), do: mover("entrada", recurso, cantidad, nil, usuario)
  def salida(recurso, cantidad, usuario), do: mover("salida", recurso, cantidad, nil, usuario)

  @doc "Descuenta en una sola llamada. Acepta un código único, {código, ubicación} o un recurso."
  def descontar(recurso, cantidad, referencia, usuario),
    do: mover("asignacion", recurso, cantidad, referencia, usuario)

  @doc "Obtiene el descuento confirmado para una necesidad, con su ubicación de origen."
  def asignacion_de(id), do: llamar({:asignacion_de, id})

  def transferir(codigo, origen, destino, cantidad, usuario \\ "sistema"),
    do: llamar({:transferir, codigo, origen, destino, cantidad, usuario})

  def listar(filtros \\ []) do
    ubicaciones =
      case Keyword.fetch(filtros, :zona) do
        {:ok, zona} -> ubicaciones_de_zona(zona)
        :error -> nil
      end

    llamar({:listar, Keyword.delete(filtros, :zona), ubicaciones})
  end

  def por_ubicacion(ubicacion), do: listar(ubicacion: ubicacion)

  def buscar_disponible(nombre, zona) do
    case Enum.find(listar(nombre: nombre, zona: zona), &(&1.cantidad > 0)) do
      nil -> {:error, :no_encontrado}
      recurso -> {:ok, recurso}
    end
  end

  @doc "Lista existencias de una categoría en una zona."
  def disponibilidad(categoria, zona), do: listar(categoria: categoria, zona: zona)

  def historial(codigo), do: llamar({:historial, codigo})

  def criticos(umbral \\ @umbral) when is_integer(umbral) and umbral >= 0,
    do: Enum.filter(listar(), &(&1.cantidad < umbral))

  def resumen, do: llamar(:resumen)

  defp mover(tipo, recurso, cantidad, referencia, usuario),
    do: llamar({:mover, tipo, recurso, cantidad, referencia, usuario})

  defp llamar(mensaje), do: GenServer.call(__MODULE__, mensaje)

  @impl true
  def init(:ok) do
    case cargar() do
      {:ok, estado} -> {:ok, estado}
      {:error, motivo} -> {:stop, motivo}
    end
  end

  @impl true
  def handle_call({:registrar, codigo, nombre, categoria, cantidad, unidad, ubicacion}, _, estado) do
    with {:ok, recurso} <- Recurso.nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion),
         :ok <- codigo_nuevo(estado, recurso.codigo) do
      guardar(estado, poner(estado, recurso), recurso)
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:mover, "asignacion", clave, cantidad, {:necesidad, id}, usuario}, _, estado) do
    case asignacion_guardada(estado, id) do
      {:ok, _} = resultado ->
        {:reply, resultado, estado}

      {:error, :no_encontrado} ->
        with {:ok, recurso} <- buscar(estado, clave),
             {:ok, actualizado} <- Recurso.salida(recurso, cantidad),
             referencia = Persistencia.unir_campos(["necesidad", id, recurso.ubicacion]),
             {:ok, movimiento} <-
               Movimiento.nuevo("asignacion", recurso.codigo, cantidad, referencia, usuario) do
          nuevo = estado |> poner(actualizado) |> registrar_movimiento(movimiento)
          guardar(estado, nuevo, {recurso.codigo, recurso.ubicacion, cantidad})
        else
          error -> {:reply, error, estado}
        end
    end
  end

  def handle_call({:mover, tipo, clave, cantidad, referencia, usuario}, _, estado) do
    with {:ok, recurso} <- buscar(estado, clave),
         {:ok, actualizado} <- ajustar(tipo, recurso, cantidad),
         referencia = referencia || recurso.ubicacion,
         {:ok, movimiento} <-
           Movimiento.nuevo(tipo, recurso.codigo, cantidad, referencia, usuario) do
      nuevo = estado |> poner(actualizado) |> registrar_movimiento(movimiento)
      guardar(estado, nuevo, actualizado)
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad, usuario}, _, estado) do
    with :ok <- validar_destino(origen, destino),
         {:ok, recurso} <- buscar(estado, {codigo, origen}),
         {:ok, restante} <- Recurso.salida(recurso, cantidad),
         receptor =
           Map.get(estado.recursos, {codigo, destino}, %{
             recurso
             | ubicacion: destino,
               cantidad: 0
           }),
         {:ok, receptor} <- Recurso.entrada(receptor, cantidad),
         referencia = "#{origen} -> #{destino}",
         {:ok, movimiento} <-
           Movimiento.nuevo("transferencia", codigo, cantidad, referencia, usuario) do
      nuevo = estado |> poner(restante) |> poner(receptor) |> registrar_movimiento(movimiento)
      guardar(estado, nuevo, receptor)
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:listar, filtros, ubicaciones}, _, estado) do
    recursos =
      estado.recursos
      |> Map.values()
      |> Enum.filter(fn recurso ->
        (ubicaciones == nil or recurso.ubicacion in ubicaciones) and
          Enum.all?(filtros, fn {campo, valor} -> Map.get(recurso, campo) == valor end)
      end)
      |> Enum.sort_by(&clave/1)

    {:reply, recursos, estado}
  end

  def handle_call({:historial, codigo}, _, estado),
    do: {:reply, Enum.filter(estado.movimientos, &(&1.recurso == codigo)), estado}

  def handle_call({:asignacion_de, id}, _, estado),
    do: {:reply, asignacion_guardada(estado, id), estado}

  def handle_call(:resumen, _, estado) do
    recursos = Map.values(estado.recursos)
    codigos = recursos |> MapSet.new(& &1.codigo) |> MapSet.size()
    criticos = Enum.count(recursos, &(&1.cantidad < @umbral))
    {:reply, %{recursos: codigos, recursos_criticos: criticos}, estado}
  end

  defp ubicaciones_de_zona(codigo) do
    case ZonaServer.obtener(codigo) do
      {:ok, zona} -> Zona.listar_codigos(zona)
      {:error, :no_encontrado} -> [codigo]
    end
  end

  defp asignacion_guardada(estado, id) do
    Enum.find_value(estado.movimientos, {:error, :no_encontrado}, fn
      %Movimiento{tipo: "asignacion", referencia: "necesidad|" <> _ = referencia} = movimiento ->
        case Persistencia.separar_campos(referencia) do
          ["necesidad", ^id, ubicacion] ->
            {:ok, {movimiento.recurso, ubicacion, movimiento.cantidad}}

          _ ->
            nil
        end

      _ ->
        nil
    end)
  end

  defp ajustar("entrada", recurso, cantidad), do: Recurso.entrada(recurso, cantidad)
  defp ajustar(_, recurso, cantidad), do: Recurso.salida(recurso, cantidad)

  defp validar_destino(origen, destino) when is_binary(destino) do
    if String.trim(destino) == "" or origen == destino,
      do: {:error, :destino_invalido},
      else: :ok
  end

  defp validar_destino(_, _), do: {:error, :destino_invalido}

  defp buscar(estado, %Recurso{} = recurso), do: buscar(estado, clave(recurso))

  defp buscar(estado, {_, _} = clave) do
    case Map.fetch(estado.recursos, clave) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, :no_encontrado}
    end
  end

  defp buscar(estado, codigo) do
    case Enum.filter(Map.values(estado.recursos), &(&1.codigo == codigo)) do
      [recurso] -> {:ok, recurso}
      [] -> {:error, :no_encontrado}
      _ -> {:error, :ubicacion_requerida}
    end
  end

  defp codigo_nuevo(estado, codigo) do
    case buscar(estado, codigo) do
      {:error, :no_encontrado} -> :ok
      _ -> {:error, :id_duplicado}
    end
  end

  defp clave(recurso), do: {recurso.codigo, recurso.ubicacion}
  defp poner(estado, recurso), do: put_in(estado.recursos[clave(recurso)], recurso)

  defp registrar_movimiento(estado, movimiento),
    do: update_in(estado.movimientos, &[movimiento | &1])

  defp cargar do
    if File.exists?(Persistencia.ruta(@pendiente)) do
      with {:ok, registros} <- Persistencia.cargar(@pendiente, &leer_registro/1) do
        {recursos, movimientos} = Enum.split_with(registros, &match?(%Recurso{}, &1))
        estado = estado(recursos, movimientos)
        publicar(estado)
        {:ok, estado}
      end
    else
      with {:ok, recursos} <- Persistencia.cargar(@recursos, &Recurso.desde_linea/1),
           {:ok, movimientos} <- Persistencia.cargar(@movimientos, &Movimiento.desde_linea/1) do
        {:ok, estado(recursos, movimientos)}
      end
    end
  end

  defp estado(recursos, movimientos) do
    %{recursos: Map.new(recursos, &{clave(&1), &1}), movimientos: movimientos}
  end

  # La copia pendiente conserva existencias e historial juntos hasta publicar ambos archivos.
  defp guardar(anterior, nuevo, resultado) do
    registros = Map.values(nuevo.recursos) ++ nuevo.movimientos

    case guardar_archivo(@pendiente, registros, &escribir_registro/1) do
      :ok ->
        publicar(nuevo)
        {:reply, {:ok, resultado}, nuevo}

      error ->
        {:reply, error, anterior}
    end
  end

  defp publicar(estado) do
    with :ok <- guardar_archivo(@recursos, Map.values(estado.recursos), &Recurso.a_linea/1),
         :ok <- guardar_archivo(@movimientos, estado.movimientos, &Movimiento.a_linea/1),
         :ok <- File.rm(Persistencia.ruta(@pendiente)) do
      :ok
    else
      {:error, motivo} -> Logger.warning("Inventario: publicación pendiente (#{inspect(motivo)})")
    end
  end

  defp guardar_archivo(archivo, registros, convertir) do
    temporal = archivo <> ".tmp"

    with :ok <- Persistencia.guardar(temporal, registros, convertir) do
      File.rename(Persistencia.ruta(temporal), Persistencia.ruta(archivo))
    end
  end

  defp escribir_registro(%Recurso{} = recurso), do: "R|" <> Recurso.a_linea(recurso)
  defp escribir_registro(%Movimiento{} = movimiento), do: "M|" <> Movimiento.a_linea(movimiento)
  defp leer_registro("R|" <> linea), do: Recurso.desde_linea(linea)
  defp leer_registro("M|" <> linea), do: Movimiento.desde_linea(linea)
  defp leer_registro(_), do: {:error, :linea_invalida}
end
