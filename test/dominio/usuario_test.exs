defmodule Emergencias.Dominio.UsuarioTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Usuario

  test "crea un usuario válido con la contraseña cifrada" do
    assert {:ok, usuario} = Usuario.nuevo("laura", "1234", "Laura Gómez", "coordinador", "centro")
    assert usuario.tipo == "coordinador"
    refute usuario.password_hash == "1234"
  end

  test "si no hay nombre completo usa el username" do
    assert {:ok, %Usuario{nombre: "laura"}} =
             Usuario.nuevo("laura", "1234", "", "ciudadano", "centro")
  end

  test "rechaza datos inválidos" do
    assert Usuario.nuevo("la", "1234", "", "ciudadano", "centro") == {:error, :usuario_invalido}

    assert Usuario.nuevo("la ura", "1234", "", "ciudadano", "centro") ==
             {:error, :usuario_invalido}

    assert Usuario.nuevo("laura", "12", "", "ciudadano", "centro") ==
             {:error, :contrasena_invalida}

    assert Usuario.nuevo("laura", "1234", "", "jefe", "centro") == {:error, :tipo_invalido}
    assert Usuario.nuevo("laura", "1234", "", "ciudadano", " ") == {:error, :zona_invalida}
  end

  test "valida la contraseña" do
    {:ok, usuario} = Usuario.nuevo("laura", "1234", "", "ciudadano", "centro")
    assert Usuario.validar_password(usuario, "1234") == :ok
    assert Usuario.validar_password(usuario, "4321") == {:error, :contrasena_incorrecta}
  end

  test "se guarda y se recupera igual desde una línea" do
    {:ok, usuario} = Usuario.nuevo("laura", "1234", "Laura Gómez", "voluntario", "zona_norte")
    assert Usuario.desde_linea(Usuario.a_linea(usuario)) == {:ok, usuario}
    assert Usuario.desde_linea("laura|abc|Laura|jefe|centro") == {:error, :linea_invalida}
  end
end
