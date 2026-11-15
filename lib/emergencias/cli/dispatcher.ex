defmodule Emergencias.CLI.Dispatcher do
  @moduledoc """
  Envía cada comando al servidor que corresponde y devuelve `{resultado, sesion}`.
  Cada integrante escribe solo en su bloque.
  """

  alias Emergencias.CLI.{Formatter, Parser, Permisos}

  alias Emergencias.Servidores.{
    ActividadLogger,
    AlbergueServer,
    AlbergueSupervisor,
    FamiliaServer,
    InventarioServer,
    MascotaServer,
    NecesidadServer,
    Sesion,
    SesionSupervisor,
    UsuarioServer,
    ZonaServer
  }

  @comandos_publicos [:connect, :help, :exit]

  @servidores_con_resumen [
    UsuarioServer,
    ZonaServer,
    InventarioServer,
    NecesidadServer,
    FamiliaServer,
    MascotaServer,
    AlbergueSupervisor
  ]

  @doc "Ejecuta el comando si hay sesión (o si es público)."
  def despachar({comando, _args} = cmd, sesion) do
    cond do
      comando in @comandos_publicos -> ejecutar(cmd, sesion)
      sesion == nil -> {{:error, :no_conectado}, sesion}
      true -> con_permiso(cmd, sesion)
    end
  end

  defp con_permiso({comando, args} = cmd, sesion) do
    if Permisos.puede?(sesion.tipo, comando) do
      linea = Enum.join([comando | args], " ")
      ActividadLogger.registrar(sesion.usuario, linea)
      Sesion.registrar_comando(sesion.usuario, linea)
      ejecutar(cmd, sesion)
    else
      {{:error, :sin_permiso}, sesion}
    end
  end

  defp ejecutar({:connect, [usuario, contrasena | resto]}, nil) when length(resto) <= 2 do
    tipo = Enum.at(resto, 0, "ciudadano")
    zona = Enum.at(resto, 1, "sin_zona")

    case UsuarioServer.connect(usuario, contrasena, tipo, zona) do
      {:ok, u, accion} ->
        nueva_sesion = %{usuario: u.username, tipo: u.tipo, zona: u.zona}
        SesionSupervisor.iniciar_sesion(nueva_sesion)
        ActividadLogger.registrar(u.username, "connect")

        mensaje =
          if accion == :registrado, do: "Usuario registrado y conectado", else: "Conectado"

        {{:ok, "#{mensaje}: #{u.username} (#{u.tipo}, zona #{u.zona})."}, nueva_sesion}

      error ->
        {error, nil}
    end
  end

  defp ejecutar({:connect, [_, _ | resto]}, sesion) when sesion != nil and length(resto) <= 2,
    do: {{:error, :sesion_activa}, sesion}

  defp ejecutar({:connect, _}, sesion),
    do: {{:error, {:uso, "connect usuario contraseña [tipo] [zona]"}}, sesion}

  defp ejecutar({:disconnect, []}, sesion) do
    cerrar(sesion)
    {{:ok, "Sesión de #{sesion.usuario} cerrada."}, nil}
  end

  defp ejecutar({:summary, []}, sesion), do: {{:ok, {:resumen, resumen_global()}}, sesion}
  defp ejecutar({:summary, _}, sesion), do: {{:error, {:uso, "summary"}}, sesion}

  defp ejecutar({:activity_log, args}, sesion) when length(args) <= 1 do
    usuario = List.first(args, :todos)

    resultado =
      case ActividadLogger.consultar(usuario) do
        {:ok, entradas} ->
          {:ok, Enum.map(entradas, fn {f, u, a} -> %{fecha: f, usuario: u, accion: a} end)}

        error ->
          error
      end

    {resultado, sesion}
  end

  defp ejecutar({:help, []}, sesion) do
    {{:ok, "Comandos disponibles:\n" <> Enum.join(Parser.comandos(), "\n")}, sesion}
  end

  defp ejecutar({:exit, []}, nil), do: {:salir, nil}

  defp ejecutar({:exit, []}, sesion) do
    cerrar(sesion)
    {:salir, nil}
  end

  # ============================== INTEGRANTE 2 ===============================

  defp ejecutar({:register_zone, [codigo, nombre, nivel | resto]}, sesion)
       when length(resto) <= 1 do
    resultado =
      with {:ok, cantidad} <- Parser.a_entero(List.first(resto, "0")) do
        ZonaServer.registrar_zona(codigo, nombre, nivel, cantidad) |> zona_registrada()
      end

    {resultado, sesion}
  end

  defp ejecutar({:register_zone, _}, sesion),
    do: {{:error, {:uso, "register_zone codigo nombre nivel [personas_afectadas]"}}, sesion}

  defp ejecutar({:register_sector, args}, sesion) do
    uso = "register_sector codigo_zona codigo_sector nombre [nivel] [personas_afectadas]"
    {registrar_nodo(args, &ZonaServer.registrar_sector/5, uso), sesion}
  end

  defp ejecutar({:register_point, args}, sesion) do
    uso = "register_point codigo_sector codigo_punto nombre [nivel] [personas_afectadas]"
    {registrar_nodo(args, &ZonaServer.registrar_punto/5, uso), sesion}
  end

  defp ejecutar({:zone_status, [codigo]}, sesion) do
    resultado =
      with {:ok, estado} <- ZonaServer.estado_zona(codigo) do
        {:ok, Formatter.estado_zona(estado)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:zone_status, _}, sesion),
    do: {{:error, {:uso, "zone_status codigo"}}, sesion}

  defp ejecutar({:zone_stats, [codigo]}, sesion), do: {ZonaServer.estadisticas(codigo), sesion}

  defp ejecutar({:zone_stats, _}, sesion),
    do: {{:error, {:uso, "zone_stats codigo"}}, sesion}

  defp ejecutar({:register_resource, [codigo, nombre, cantidad, unidad, ubicacion]}, sesion),
    do:
      ejecutar(
        {:register_resource, [codigo, nombre, nombre, cantidad, unidad, ubicacion]},
        sesion
      )

  defp ejecutar(
         {:register_resource, [codigo, nombre, categoria, cantidad, unidad, ubicacion]},
         sesion
       ) do
    resultado =
      with {:ok, numero} <- Parser.a_entero(cantidad) do
        InventarioServer.registrar_recurso(codigo, nombre, categoria, numero, unidad, ubicacion)
      end

    {resultado, sesion}
  end

  defp ejecutar({:register_resource, _}, sesion),
    do:
      {{:error, {:uso, "register_resource codigo nombre [categoria] cantidad unidad ubicacion"}},
       sesion}

  defp ejecutar({comando, [codigo, cantidad | ubicacion]}, sesion)
       when comando in [:resource_entry, :resource_exit] and length(ubicacion) <= 1 do
    clave =
      case ubicacion do
        [] -> codigo
        [lugar] -> {codigo, lugar}
      end

    operacion =
      if comando == :resource_entry,
        do: &InventarioServer.entrada/3,
        else: &InventarioServer.salida/3

    resultado =
      with {:ok, numero} <- Parser.a_entero_positivo(cantidad) do
        operacion.(clave, numero, sesion.usuario)
      end

    {resultado, sesion}
  end

  defp ejecutar({comando, _}, sesion) when comando in [:resource_entry, :resource_exit],
    do: {{:error, {:uso, "#{comando} codigo cantidad [ubicacion]"}}, sesion}

  defp ejecutar({:list_resources, args}, sesion) do
    resultado =
      with {:ok, filtros} <- Parser.parsear_filtros(args),
           :ok <- validar_filtros_inventario(filtros) do
        filtros =
          Enum.map(filtros, fn
            {:tipo, valor} -> {:categoria, valor}
            filtro -> filtro
          end)

        {:ok, InventarioServer.listar(filtros)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:transfer_resource, [codigo, origen, destino, cantidad]}, sesion) do
    resultado =
      with {:ok, numero} <- Parser.a_entero_positivo(cantidad) do
        InventarioServer.transferir(codigo, origen, destino, numero, sesion.usuario)
      end

    {resultado, sesion}
  end

  defp ejecutar({:transfer_resource, _}, sesion),
    do: {{:error, {:uso, "transfer_resource codigo origen destino cantidad"}}, sesion}

  defp ejecutar({:resource_history, [codigo]}, sesion),
    do: {{:ok, InventarioServer.historial(codigo)}, sesion}

  defp ejecutar({:resource_history, _}, sesion),
    do: {{:error, {:uso, "resource_history codigo"}}, sesion}

  defp ejecutar({:critical_resources, []}, sesion),
    do: {{:ok, InventarioServer.criticos()}, sesion}

  defp ejecutar({:critical_resources, [umbral]}, sesion) do
    resultado =
      with {:ok, numero} when numero >= 0 <- Parser.a_entero(umbral) do
        {:ok, InventarioServer.criticos(numero)}
      else
        {:ok, _} -> {:error, :cantidad_invalida}
        error -> error
      end

    {resultado, sesion}
  end

  defp ejecutar({:critical_resources, _}, sesion),
    do: {{:error, {:uso, "critical_resources [umbral]"}}, sesion}

  defp ejecutar({:register_need, [tipo, cantidad, prioridad, zona, descripcion | resto]}, sesion)
       when length(resto) <= 1 do
    resultado =
      with {:ok, numero} <- Parser.a_entero_positivo(cantidad) do
        NecesidadServer.registrar(
          tipo,
          numero,
          prioridad,
          zona,
          descripcion,
          sesion.usuario,
          List.first(resto)
        )
      end

    {resultado, sesion}
  end

  defp ejecutar({:register_need, _}, sesion),
    do:
      {{:error, {:uso, "register_need tipo cantidad prioridad zona descripcion [albergue]"}},
       sesion}

  defp ejecutar({:list_needs, args}, sesion) do
    resultado =
      with {:ok, filtros} <- Parser.parsear_filtros(args),
           :ok <- validar_filtros_necesidades(filtros) do
        {:ok, NecesidadServer.listar(filtros)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:update_need, [id, estado]}, sesion),
    do: {NecesidadServer.cambiar_estado(id, estado), sesion}

  defp ejecutar({:update_need, _}, sesion),
    do: {{:error, {:uso, "update_need id en_atencion|atendida|cancelada"}}, sesion}

  defp ejecutar({:assign_resource, [id, recurso, cantidad | resto]}, sesion)
       when length(resto) <= 1 do
    selector =
      case resto do
        [] -> recurso
        [ubicacion] -> {recurso, ubicacion}
      end

    resultado =
      with {:ok, numero} <- Parser.a_entero_positivo(cantidad) do
        NecesidadServer.asignar_recurso(id, selector, numero, sesion.usuario)
      end

    {resultado, sesion}
  end

  defp ejecutar({:assign_resource, _}, sesion),
    do: {{:error, {:uso, "assign_resource id recurso cantidad [ubicacion]"}}, sesion}

  defp ejecutar({:pending_needs, []}, sesion), do: {{:ok, NecesidadServer.pendientes()}, sesion}

  defp ejecutar({:pending_needs, _}, sesion),
    do: {{:error, {:uso, "pending_needs"}}, sesion}

  # ============================== INTEGRANTE 3 ===============================

  defp ejecutar({:register_shelter, [codigo, nombre, zona, capacidad]}, sesion) do
    resultado =
      with {:ok, numero} <- Parser.a_entero(capacidad),
           {:ok, albergue} <- AlbergueSupervisor.crear_albergue(codigo, nombre, zona, numero) do
        {:ok,
         "Albergue registrado: #{albergue.nombre} (#{albergue.codigo}), capacidad #{albergue.capacidad}."}
      end

    {resultado, sesion}
  end

  defp ejecutar({:register_shelter, _}, sesion),
    do: {{:error, {:uso, "register_shelter codigo nombre zona capacidad"}}, sesion}

  defp ejecutar({:check_shelter, [codigo]}, sesion),
    do: {AlbergueServer.consultar(codigo), sesion}

  defp ejecutar({:check_shelter, _}, sesion),
    do: {{:error, {:uso, "check_shelter codigo"}}, sesion}

  defp ejecutar({:list_shelters, []}, sesion), do: {AlbergueSupervisor.listar(), sesion}

  defp ejecutar({:list_shelters, _}, sesion), do: {{:error, {:uso, "list_shelters"}}, sesion}

  defp ejecutar({:register_entry, [codigo, documento]}, sesion) do
    {movimiento_albergue(
       AlbergueServer.registrar_entrada(codigo, documento),
       "Ingreso registrado"
     ), sesion}
  end

  defp ejecutar({:register_entry, _}, sesion),
    do: {{:error, {:uso, "register_entry codigo_albergue documento"}}, sesion}

  defp ejecutar({:register_exit, [codigo, documento]}, sesion) do
    {movimiento_albergue(AlbergueServer.registrar_salida(codigo, documento), "Salida registrada"),
     sesion}
  end

  defp ejecutar({:register_exit, _}, sesion),
    do: {{:error, {:uso, "register_exit codigo_albergue documento"}}, sesion}

  defp ejecutar({:shelter_report, []}, sesion), do: {AlbergueSupervisor.mas_ocupados(), sesion}

  defp ejecutar({:shelter_report, [limite]}, sesion) do
    resultado =
      with {:ok, numero} <- Parser.a_entero_positivo(limite) do
        AlbergueSupervisor.mas_ocupados(numero)
      end

    {resultado, sesion}
  end

  defp ejecutar({:shelter_report, _}, sesion),
    do: {{:error, {:uso, "shelter_report [cantidad]"}}, sesion}

  defp ejecutar({:report_person, [documento, nombre, edad, zona | resto]}, sesion)
       when length(resto) <= 1 do
    estado = List.first(resto, "reportada")

    resultado =
      with {:ok, edad} <- leer_edad(edad),
           {:ok, persona} <- FamiliaServer.reportar_persona(documento, nombre, edad, zona, estado) do
        {:ok, sin_historial(persona)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:report_person, _}, sesion),
    do: {{:error, {:uso, "report_person documento nombre edad|- zona [estado]"}}, sesion}

  defp ejecutar({:find_person, [documento]}, sesion) do
    resultado =
      with {:ok, persona} <- FamiliaServer.buscar(documento) do
        {:ok, sin_historial(persona)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:find_person, _}, sesion),
    do: {{:error, {:uso, "find_person documento"}}, sesion}

  defp ejecutar({:search_persons, args}, sesion) do
    resultado =
      with {:ok, filtros} <- Parser.parsear_filtros(args),
           {:ok, personas} <- FamiliaServer.buscar_por(filtros) do
        {:ok, Enum.map(personas, &sin_historial/1)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:update_person, [documento, estado]}, sesion) do
    resultado =
      with {:ok, persona} <- FamiliaServer.cambiar_estado(documento, estado, sesion.usuario) do
        {:ok, sin_historial(persona)}
      end

    {resultado, sesion}
  end

  defp ejecutar({:update_person, _}, sesion),
    do: {{:error, {:uso, "update_person documento estado"}}, sesion}

  defp ejecutar({:person_history, [documento]}, sesion),
    do: {FamiliaServer.historial(documento), sesion}

  defp ejecutar({:person_history, _}, sesion),
    do: {{:error, {:uso, "person_history documento"}}, sesion}

  defp ejecutar({:send_family_message, [documento, contenido]}, sesion),
    do: {FamiliaServer.enviar_mensaje(sesion.usuario, documento, contenido), sesion}

  defp ejecutar({:send_family_message, _}, sesion),
    do: {{:error, {:uso, "send_family_message documento \"mensaje\""}}, sesion}

  defp ejecutar({:list_family_messages, [documento]}, sesion),
    do: {FamiliaServer.listar_mensajes(documento), sesion}

  defp ejecutar({:list_family_messages, _}, sesion),
    do: {{:error, {:uso, "list_family_messages documento"}}, sesion}

  defp ejecutar({:mark_message, [id, estado]}, sesion),
    do: {FamiliaServer.marcar_mensaje(id, estado), sesion}

  defp ejecutar({:mark_message, _}, sesion),
    do: {{:error, {:uso, "mark_message id entregado|pendiente"}}, sesion}

  defp ejecutar(
         {:report_pet, [tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto]},
         sesion
       ) do
    datos = %{
      especie: especie,
      nombre: nombre,
      caracteristicas: caracteristicas,
      color: color,
      tamano: tamano,
      zona: zona,
      contacto: contacto
    }

    resultado =
      case MascotaServer.reportar(tipo, datos) do
        {:error, :tipo_invalido} -> {:error, :tipo_reporte_invalido}
        otro -> otro
      end

    {resultado, sesion}
  end

  defp ejecutar({:report_pet, _}, sesion),
    do:
      {{:error,
        {:uso,
         "report_pet lost|found especie nombre \"caracteristicas\" color tamano zona contacto"}},
       sesion}

  defp ejecutar({:list_pets, args}, sesion) do
    resultado =
      with {:ok, filtros} <- Parser.parsear_filtros(args) do
        MascotaServer.listar(filtros)
      end

    {resultado, sesion}
  end

  defp ejecutar({:match_pets, []}, sesion), do: {MascotaServer.buscar_coincidencias(), sesion}

  defp ejecutar({:match_pets, _}, sesion), do: {{:error, {:uso, "match_pets"}}, sesion}

  defp ejecutar({:confirm_match, [id_a, id_b]}, sesion) do
    resultado =
      with {:ok, [a, b]} <- MascotaServer.confirmar_coincidencia(id_a, id_b) do
        {:ok, "Coincidencia confirmada: #{a.id} y #{b.id} quedan resueltos."}
      end

    {resultado, sesion}
  end

  defp ejecutar({:confirm_match, _}, sesion),
    do: {{:error, {:uso, "confirm_match id_perdida id_encontrada"}}, sesion}

  # Debe ir de última.
  defp ejecutar({comando, _args}, sesion),
    do: {{:error, {:comando_no_implementado, comando}}, sesion}

  defp registrar_nodo([padre, codigo, nombre | resto], registrar, _uso) when length(resto) <= 2 do
    nivel = List.first(resto)

    with {:ok, cantidad} <- Parser.a_entero(Enum.at(resto, 1, "0")) do
      registrar.(padre, codigo, nombre, nivel, cantidad) |> zona_registrada()
    end
  end

  defp registrar_nodo(_args, _registrar, uso), do: {:error, {:uso, uso}}

  defp zona_registrada({:ok, nodo}), do: {:ok, "Registrado: #{nodo.nombre} (#{nodo.codigo})."}
  defp zona_registrada(error), do: error

  defp validar_filtros_necesidades(filtros) do
    validar_filtros(filtros, [:zona, :tipo, :prioridad, :estado, :albergue])
  end

  defp validar_filtros_inventario(filtros) do
    validar_filtros(filtros, [:tipo, :categoria, :zona, :ubicacion, :nombre])
  end

  defp validar_filtros(filtros, permitidos) do
    case Enum.find(filtros, fn {campo, _} -> campo not in permitidos end) do
      nil -> :ok
      {campo, valor} -> {:error, {:filtro_invalido, "#{campo}=#{valor}"}}
    end
  end

    defp movimiento_albergue({:ok, albergue}, accion) do
    datos = AlbergueServer.resumen_albergue(albergue)

    {:ok,
     "#{accion} en #{datos.codigo}. Ocupación: #{datos.ocupacion}/#{datos.capacidad} " <>
       "(#{datos.cupos} cupos libres)."}
  end

  defp movimiento_albergue(error, _accion), do: error

  defp leer_edad(texto) when texto in ["-", "?"], do: {:ok, nil}
  defp leer_edad(texto), do: Parser.a_entero(texto)

  defp sin_historial(persona), do: Map.delete(persona, :historial)

  defp cerrar(sesion) do
    UsuarioServer.disconnect(sesion.usuario)
    SesionSupervisor.cerrar_sesion(sesion.usuario)
  end
  
  defp resumen_global do
    @servidores_con_resumen
    |> Enum.reduce(%{}, fn servidor, total -> Map.merge(total, resumen_de(servidor)) end)
    |> Map.put(:sesiones_activas, SesionSupervisor.sesiones_activas())
  end

  # Si un servidor no está activo, su parte del resumen queda vacía.
  defp resumen_de(servidor) do
    servidor.resumen()
  catch
    :exit, _ -> %{}
  end
end
