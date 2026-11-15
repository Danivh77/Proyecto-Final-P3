defmodule Emergencias.CLI.Dispatcher do
  @moduledoc """
  Envía cada comando al servidor que corresponde y devuelve `{resultado, sesion}`.
  Cada integrante escribe solo en su bloque.
  """

  alias Emergencias.CLI.{Parser, Permisos}

  alias Emergencias.Servidores.{
    ActividadLogger,
    Sesion,
    SesionSupervisor,
    UsuarioServer,
    ZonaServer
  }

  @comandos_publicos [:connect, :help, :exit]

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

  defp ejecutar({:summary, []}, sesion), do: {{:error, :no_implementado}, sesion}

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

  defp ejecutar({:zone_status, [codigo]}, sesion), do: {ZonaServer.estado_zona(codigo), sesion}

  defp ejecutar({:zone_status, _}, sesion),
    do: {{:error, {:uso, "zone_status codigo"}}, sesion}

  defp ejecutar({:zone_stats, [codigo]}, sesion), do: {ZonaServer.estadisticas(codigo), sesion}

  defp ejecutar({:zone_stats, _}, sesion),
    do: {{:error, {:uso, "zone_stats codigo"}}, sesion}

  # ============================== INTEGRANTE 3 ===============================

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

  defp cerrar(sesion) do
    UsuarioServer.disconnect(sesion.usuario)
    SesionSupervisor.cerrar_sesion(sesion.usuario)
  end
end
