defmodule Emergencias.Servidores.UsuarioServerTest do
  use ExUnit.Case, async: false

  alias Emergencias.Servidores.UsuarioServer

  defp nombre_unico, do: "u" <> Base.encode16(:crypto.strong_rand_bytes(6))

  test "registra automáticamente a un usuario nuevo" do
    nombre = nombre_unico()

    assert {:ok, usuario, :registrado} =
             UsuarioServer.connect(nombre, "1234", "voluntario", "centro")

    assert usuario.tipo == "voluntario"
    assert UsuarioServer.conectado?(nombre)
  end

  test "valida la contraseña de un usuario que ya existe" do
    nombre = nombre_unico()
    UsuarioServer.connect(nombre, "1234", "coordinador", "centro")
    UsuarioServer.disconnect(nombre)

    assert UsuarioServer.connect(nombre, "mala", "coordinador", "centro") ==
             {:error, :contrasena_incorrecta}

    assert {:ok, _, :autenticado} = UsuarioServer.connect(nombre, "1234", "ciudadano", "otra")
  end

  test "un usuario existente conserva su tipo y zona originales" do
    nombre = nombre_unico()
    UsuarioServer.connect(nombre, "1234", "coordinador", "centro")
    UsuarioServer.disconnect(nombre)

    assert {:ok, usuario, :autenticado} =
             UsuarioServer.connect(nombre, "1234", "ciudadano", "otra")

    assert {usuario.tipo, usuario.zona} == {"coordinador", "centro"}
  end

  test "no se puede conectar dos veces el mismo usuario" do
    nombre = nombre_unico()
    UsuarioServer.connect(nombre, "1234", "ciudadano", "centro")
    assert UsuarioServer.connect(nombre, "1234", "ciudadano", "centro") == {:error, :ya_conectado}
  end

  test "desconectar" do
    nombre = nombre_unico()
    UsuarioServer.connect(nombre, "1234", "ciudadano", "centro")

    assert UsuarioServer.disconnect(nombre) == :ok
    refute UsuarioServer.conectado?(nombre)
    assert UsuarioServer.disconnect(nombre) == {:error, :no_conectado}
  end

  test "rechaza datos inválidos al registrar" do
    assert UsuarioServer.connect(nombre_unico(), "1234", "jefe", "centro") ==
             {:error, :tipo_invalido}
  end
end
