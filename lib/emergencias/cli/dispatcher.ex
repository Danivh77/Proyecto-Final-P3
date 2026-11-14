defmodule Emergencias.CLI.Dispatcher do
  @moduledoc """
  Envía cada comando al servidor que corresponde y devuelve `{resultado, sesion}`.
  Cada integrante escribe solo en su bloque.
  """

  alias Emergencias.CLI.Parser
  alias Emergencias.Servidores.ActividadLogger

  @comandos_publicos [:connect, :help, :exit]
  @tipos_usuario ~w(ciudadano voluntario coordinador administrador)

  @doc "Ejecuta el comando si hay sesión (o si es público)."
  def despachar({comando, _args} = cmd, sesion) do
    cond do
      comando in @comandos_publicos -> ejecutar(cmd, sesion)
      sesion == nil -> {{:error, :no_conectado}, sesion}
      true -> con_permiso(cmd, sesion)
    end
  end

  # TODO: validar permisos con Permisos.puede?/2.
  defp con_permiso({comando, args} = cmd, sesion) do
    ActividadLogger.registrar(sesion.usuario, Enum.join([comando | args], " "))
    ejecutar(cmd, sesion)
  end

  # TODO: validar la contraseña con UsuarioServer.connect/4.
  defp ejecutar({:connect, [usuario, _contrasena | resto]}, sesion) when length(resto) <= 2 do
    tipo = Enum.at(resto, 0, "ciudadano")
    zona = Enum.at(resto, 1, "sin_zona")

    if tipo in @tipos_usuario do
      ActividadLogger.registrar(usuario, "connect")

      {{:ok, "Conectado como #{usuario} (#{tipo}, zona #{zona})."},
       %{usuario: usuario, tipo: tipo, zona: zona}}
    else
      {{:error, :tipo_invalido}, sesion}
    end
  end

  defp ejecutar({:connect, _}, sesion),
    do: {{:error, {:uso, "connect usuario contraseña [tipo] [zona]"}}, sesion}

  defp ejecutar({:disconnect, []}, sesion),
    do: {{:ok, "Sesión de #{sesion.usuario} cerrada."}, nil}

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

  defp ejecutar({:exit, []}, sesion), do: {:salir, sesion}

  # ============================== INTEGRANTE 2 ===============================



  # ============================== INTEGRANTE 3 ===============================



  # Debe ir de última.
  defp ejecutar({comando, _args}, sesion),
    do: {{:error, {:comando_no_implementado, comando}}, sesion}
end
