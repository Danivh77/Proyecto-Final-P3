defmodule Emergencias.Servidores.NecesidadServer do
  @moduledoc "Registra necesidades y coordina su asignación con el inventario."

  use GenServer

  alias Emergencias.Dominio.{Albergue, Necesidad, Recurso}
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.{AlbergueServer, InventarioServer, ZonaServer}
  alias Emergencias.Util.Ids

  @archivo "necesidades.txt"
  @temporal @archivo <> ".tmp"

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar(tipo, cantidad, prioridad, zona, descripcion, responsable, albergue \\ nil),
    do: llamar({:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable, albergue})

  def obtener(id), do: llamar({:obtener, id})
  def listar(filtros \\ []), do: llamar({:listar, filtros})
  def reservar(id), do: llamar({:reservar, id})
  def confirmar_asignacion(id, recurso, cantidad), do: llamar({:confirmar, id, recurso, cantidad})
  def revertir(id), do: llamar({:revertir, id})
  def cambiar_estado(id, estado), do: llamar({:cambiar_estado, id, estado})
  def pendientes, do: listar(estado: "pendiente")
  def por_albergue(codigo), do: listar(albergue: codigo)
  def resumen, do: llamar(:resumen)

  def siguiente_a_atender do
    case pendientes() do
      [primera | _] -> {:ok, primera}
      [] -> {:error, :no_encontrado}
    end
  end

  @doc """
  Reserva la solicitud, descuenta inventario y confirma la asignación.
  El recurso se puede indicar por código, nombre en la zona o {código, ubicación}.
  """
  def asignar_recurso(id, recurso, cantidad, usuario),
    do: llamar({:asignar, id, recurso, cantidad, usuario})

  defp llamar(mensaje), do: GenServer.call(__MODULE__, mensaje, :infinity)

  @impl true
  def init(:ok) do
    with {:ok, registros} <- Persistencia.cargar(@archivo, &Necesidad.desde_linea/1),
         necesidades = Map.new(registros, &{&1.id, &1}),
         {:ok, recuperadas} <- recuperar_reservas(necesidades) do
      {:ok, recuperadas}
    else
      {:error, motivo} -> {:stop, motivo}
    end
  end

  @impl true
  def handle_call(
        {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable, albergue},
        _,
        datos
      ) do
    id = Ids.siguiente("N", datos)

    with {:ok, necesidad} <-
           Necesidad.nuevo(id, tipo, descripcion, cantidad, zona, prioridad, responsable),
         :ok <- validar_zona(zona),
         {:ok, codigo_albergue} <- validar_albergue(albergue) do
      responder_guardado(datos, {:ok, %{necesidad | albergue: codigo_albergue}})
    else
      error -> {:reply, error, datos}
    end
  end

  def handle_call({:obtener, id}, _, datos), do: {:reply, buscar(datos, id), datos}

  def handle_call({:listar, filtros}, _, datos) do
    lista =
      datos
      |> Map.values()
      |> Necesidad.filtrar(filtros)
      |> Enum.sort_by(fn %{id: id} -> {byte_size(id), id} end)
      |> Necesidad.ordenar_por_prioridad()

    {:reply, lista, datos}
  end

  def handle_call(:resumen, _, datos) do
    estados = datos |> Map.values() |> Enum.frequencies_by(& &1.estado)

    resumen = %{
      necesidades: map_size(datos),
      necesidades_pendientes: Map.get(estados, "pendiente", 0),
      necesidades_asignadas: Map.get(estados, "asignada", 0),
      necesidades_en_atencion: Map.get(estados, "en_atencion", 0),
      necesidades_atendidas: Map.get(estados, "atendida", 0),
      necesidades_canceladas: Map.get(estados, "cancelada", 0)
    }

    {:reply, resumen, datos}
  end

  def handle_call({:reservar, id}, _, datos) do
    resultado = with {:ok, necesidad} <- buscar(datos, id), do: reservar_necesidad(necesidad)
    responder_guardado(datos, resultado)
  end

  def handle_call({:confirmar, id, recurso, cantidad}, _, datos) do
    resultado =
      with {:ok, necesidad} <- buscar(datos, id),
           {:ok, {codigo, ubicacion, ^cantidad} = asignacion} <-
             InventarioServer.asignacion_de(id),
           true <-
             recurso in [codigo, {codigo, ubicacion}] or
               match?(%Recurso{codigo: ^codigo, ubicacion: ^ubicacion}, recurso) do
        confirmar(necesidad, asignacion)
      else
        {:error, _} = error -> error
        _ -> {:error, :asignacion_invalida}
      end

    responder_guardado(datos, resultado)
  end

  def handle_call({:revertir, id}, _, datos) do
    resultado =
      with {:ok, necesidad} <- buscar(datos, id),
           {:error, :no_encontrado} <- InventarioServer.asignacion_de(id) do
        Necesidad.transicion(necesidad, "pendiente")
      else
        {:ok, _} -> {:error, :ya_asignada}
        error -> error
      end

    responder_guardado(datos, resultado)
  end

  def handle_call({:cambiar_estado, id, estado}, _, datos)
      when estado in ["en_atencion", "atendida", "cancelada"] do
    resultado =
      with {:ok, necesidad} <- buscar(datos, id),
           :ok <- sin_reserva(necesidad) do
        Necesidad.transicion(necesidad, estado)
      end

    responder_guardado(datos, resultado)
  end

  def handle_call({:cambiar_estado, _, _}, _, datos),
    do: {:reply, {:error, :transicion_invalida}, datos}

  def handle_call({:asignar, id, recurso, cantidad, usuario}, _, datos) do
    with {:ok, necesidad} <- buscar(datos, id) do
      asignar(datos, necesidad, recurso, cantidad, usuario)
    else
      error -> {:reply, error, datos}
    end
  end

  defp asignar(datos, %Necesidad{estado: "asignada", asignaciones: []} = necesidad, _, _, _) do
    case InventarioServer.asignacion_de(necesidad.id) do
      {:ok, asignacion} -> responder_guardado(datos, confirmar(necesidad, asignacion))
      {:error, :no_encontrado} -> {:reply, {:error, :reserva_activa}, datos}
    end
  end

  defp asignar(datos, necesidad, selector, cantidad, usuario) do
    with {:ok, reservada} <- reservar_necesidad(necesidad),
         :ok <- validar_cantidad(necesidad, cantidad),
         {:ok, recurso} <- seleccionar_recurso(selector, necesidad.zona, cantidad),
         {:ok, actualizados} <- guardar(datos, reservada) do
      case InventarioServer.descontar(recurso, cantidad, {:necesidad, reservada.id}, usuario) do
        {:ok, asignacion} ->
          responder_guardado(actualizados, confirmar(reservada, asignacion))

        {:error, _} = error ->
          {:ok, pendiente} = Necesidad.transicion(reservada, "pendiente")

          case guardar(actualizados, pendiente) do
            {:ok, revertidos} -> {:reply, error, revertidos}
            error_guardado -> {:reply, error_guardado, actualizados}
          end
      end
    else
      error -> {:reply, error, datos}
    end
  end

  defp reservar_necesidad(%Necesidad{estado: "pendiente"} = necesidad),
    do: Necesidad.transicion(necesidad, "asignada")

  defp reservar_necesidad(%Necesidad{estado: estado}) when estado in ["atendida", "cancelada"],
    do: {:error, :ya_resuelto}

  defp reservar_necesidad(%Necesidad{}), do: {:error, :ya_asignada}

  defp confirmar(%Necesidad{estado: "asignada", asignaciones: []} = necesidad, asignacion),
    do: {:ok, %{necesidad | asignaciones: [asignacion]}}

  defp confirmar(%Necesidad{} = necesidad, _asignacion),
    do: {:error, if(necesidad.asignaciones == [], do: :transicion_invalida, else: :ya_asignada)}

  defp sin_reserva(%Necesidad{estado: "asignada", asignaciones: []}),
    do: {:error, :reserva_activa}

  defp sin_reserva(_), do: :ok

  defp seleccionar_recurso({_, _} = clave, _zona, _cantidad), do: {:ok, clave}
  defp seleccionar_recurso(%Recurso{} = recurso, _zona, _cantidad), do: {:ok, recurso}

  defp seleccionar_recurso(codigo_o_nombre, zona, cantidad) when is_binary(codigo_o_nombre) do
    case InventarioServer.listar(codigo: codigo_o_nombre) do
      [] ->
        recursos = InventarioServer.listar(nombre: codigo_o_nombre, zona: zona)

        case Enum.find(recursos, &Recurso.puede_cubrir?(&1, cantidad)) do
          nil when recursos == [] -> {:error, :no_encontrado}
          nil -> {:error, :inventario_insuficiente}
          recurso -> {:ok, recurso}
        end

      [_recurso] ->
        {:ok, codigo_o_nombre}

      _ ->
        {:error, :ubicacion_requerida}
    end
  end

  defp seleccionar_recurso(_, _, _), do: {:error, :asignacion_invalida}

  defp validar_cantidad(%Necesidad{cantidad: solicitada}, cantidad)
       when is_integer(cantidad) and cantidad > 0 and cantidad <= solicitada,
       do: :ok

  defp validar_cantidad(_, _), do: {:error, :cantidad_asignacion_invalida}

  defp validar_zona(zona) do
    if ZonaServer.existe?(zona), do: :ok, else: {:error, :zona_no_encontrada}
  end

  defp validar_albergue(nil), do: {:ok, nil}

  defp validar_albergue(codigo) do
    case Albergue.normalizar_codigo(codigo) do
      invalido when invalido in [nil, ""] ->
        {:error, :albergue_invalido}

      normalizado ->
        with {:ok, _} <- AlbergueServer.obtener(normalizado), do: {:ok, normalizado}
    end
  end

  defp buscar(datos, id) do
    case Map.fetch(datos, id) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, :no_encontrado}
    end
  end

  defp responder_guardado(datos, {:ok, necesidad}) do
    case guardar(datos, necesidad) do
      {:ok, actualizados} -> {:reply, {:ok, necesidad}, actualizados}
      error -> {:reply, error, datos}
    end
  end

  defp responder_guardado(datos, error), do: {:reply, error, datos}

  defp guardar(datos, necesidad),
    do: datos |> Map.put(necesidad.id, necesidad) |> persistir()

  defp persistir(datos) do
    with :ok <- Persistencia.guardar(@temporal, Map.values(datos), &Necesidad.a_linea/1),
         :ok <- File.rename(Persistencia.ruta(@temporal), Persistencia.ruta(@archivo)) do
      {:ok, datos}
    end
  end

  # Si el proceso se detuvo tras reservar, el historial de inventario indica si ya descontó.
  defp recuperar_reservas(datos) do
    recuperados =
      Map.new(datos, fn
        {id, %Necesidad{estado: "asignada", asignaciones: []} = necesidad} ->
          {:ok, recuperada} =
            case InventarioServer.asignacion_de(id) do
              {:ok, asignacion} -> confirmar(necesidad, asignacion)
              {:error, :no_encontrado} -> Necesidad.transicion(necesidad, "pendiente")
            end

          {id, recuperada}

        entrada ->
          entrada
      end)

    if recuperados == datos, do: {:ok, datos}, else: persistir(recuperados)
  end
end
