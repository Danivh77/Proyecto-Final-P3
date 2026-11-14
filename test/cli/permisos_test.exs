defmodule Emergencias.CLI.PermisosTest do
  use ExUnit.Case, async: true

  alias Emergencias.CLI.Permisos

  test "un ciudadano puede reportar pero no gestionar recursos" do
    assert Permisos.puede?("ciudadano", :report_person)
    assert Permisos.puede?("ciudadano", :register_need)
    refute Permisos.puede?("ciudadano", :register_resource)
    refute Permisos.puede?("ciudadano", :assign_resource)
  end

  test "un voluntario registra recursos y entradas, pero no asigna" do
    assert Permisos.puede?("voluntario", :register_resource)
    assert Permisos.puede?("voluntario", :register_entry)
    refute Permisos.puede?("voluntario", :assign_resource)
  end

  test "un coordinador asigna y registra zonas, pero no ve la actividad" do
    assert Permisos.puede?("coordinador", :assign_resource)
    assert Permisos.puede?("coordinador", :register_zone)
    refute Permisos.puede?("coordinador", :activity_log)
  end

  test "un administrador puede hacer todo" do
    assert Permisos.acciones_de("administrador") |> length() ==
             length(Emergencias.CLI.Parser.comandos())
  end

  test "un tipo desconocido no puede hacer nada" do
    assert Permisos.acciones_de("jefe") == []
  end
end
