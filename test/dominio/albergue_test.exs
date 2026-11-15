defmodule Emergencias.Dominio.AlbergueTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Albergue

  defp albergue(capacidad \\ 3) do
    {:ok, albergue} = Albergue.nuevo("A01", "Albergue Norte", "zona_norte", capacidad)
    albergue
  end

  describe "nuevo/4" do
    test "crea un albergue vacío y pone el código en mayúsculas" do
      assert {:ok, a} = Albergue.nuevo(" a01 ", "Albergue Norte", "zona_norte", 150)
      assert a.codigo == "A01"
      assert a.capacidad == 150
      assert Albergue.ocupacion(a) == 0
      assert Albergue.cupos(a) == 150
    end

    test "rechaza capacidades negativas, cero o no enteras" do
      assert {:error, :capacidad_invalida} = Albergue.nuevo("A01", "N", "z", -5)
      assert {:error, :capacidad_invalida} = Albergue.nuevo("A01", "N", "z", 0)
      assert {:error, :capacidad_invalida} = Albergue.nuevo("A01", "N", "z", "150")
    end

    test "rechaza códigos que no sirven como nombre de archivo" do
      assert {:error, :codigo_invalido} = Albergue.nuevo("", "N", "z", 10)
      assert {:error, :codigo_invalido} = Albergue.nuevo("../A01", "N", "z", 10)
      assert {:error, :codigo_invalido} = Albergue.nuevo("A 01", "N", "z", 10)
      assert {:error, :codigo_invalido} = Albergue.nuevo(nil, "N", "z", 10)
    end

    test "rechaza nombre o zona vacíos o con el separador" do
      assert {:error, :datos_invalidos} = Albergue.nuevo("A01", "", "z", 10)
      assert {:error, :datos_invalidos} = Albergue.nuevo("A01", "Norte\nSur", "z", 10)
      assert {:error, :datos_invalidos} = Albergue.nuevo("A01", "N", "  ", 10)
    end
  end

  describe "ingresar/2 y salir/2" do
    test "registra el ingreso y calcula cupos y porcentaje" do
      {:ok, a} = Albergue.ingresar(albergue(4), "100")
      assert Albergue.ocupacion(a) == 1
      assert Albergue.cupos(a) == 3
      assert Albergue.porcentaje_ocupacion(a) == 25.0
    end

    test "no permite ingresar dos veces a la misma persona" do
      {:ok, a} = Albergue.ingresar(albergue(), "100")
      assert {:error, :ya_esta_dentro} = Albergue.ingresar(a, "100")
      assert Albergue.ocupacion(a) == 1
    end

    test "no supera la capacidad máxima" do
      {:ok, a} = Albergue.ingresar(albergue(2), "1")
      {:ok, a} = Albergue.ingresar(a, "2")
      assert {:error, :capacidad_llena} = Albergue.ingresar(a, "3")
      assert Albergue.ocupacion(a) == 2
      assert Albergue.cupos(a) == 0
      assert Albergue.porcentaje_ocupacion(a) == 100.0
    end

    test "una persona que ya está dentro recibe :ya_esta_dentro aunque esté lleno" do
      {:ok, a} = Albergue.ingresar(albergue(1), "1")
      assert {:error, :ya_esta_dentro} = Albergue.ingresar(a, "1")
    end

    test "rechaza documentos inválidos" do
      assert {:error, :documento_invalido} = Albergue.ingresar(albergue(), "")
      assert {:error, :documento_invalido} = Albergue.ingresar(albergue(), "1,2")
      assert {:error, :documento_invalido} = Albergue.ingresar(albergue(), nil)
    end

    test "la salida libera el cupo y falla si la persona no estaba" do
      {:ok, a} = Albergue.ingresar(albergue(), "100")
      assert {:error, :no_esta_dentro} = Albergue.salir(a, "999")
      assert {:ok, a} = Albergue.salir(a, "100")
      assert Albergue.ocupacion(a) == 0
      assert {:error, :no_esta_dentro} = Albergue.salir(a, "100")
    end
  end

  describe "asociar_recurso/2 y asociar_necesidad/2" do
    test "asocia sin repetir" do
      {:ok, a} = Albergue.asociar_recurso(albergue(), "R001")
      assert a.recursos == ["R001"]
      assert {:error, :ya_asociado} = Albergue.asociar_recurso(a, "R001")

      {:ok, a} = Albergue.asociar_necesidad(a, "N001")
      {:ok, a} = Albergue.asociar_necesidad(a, "N002")
      assert a.necesidades == ["N001", "N002"]
      assert {:error, :ya_asociado} = Albergue.asociar_necesidad(a, "N002")
    end

    test "rechaza valores vacíos" do
      assert {:error, :datos_invalidos} = Albergue.asociar_recurso(albergue(), "")
      assert {:error, :datos_invalidos} = Albergue.asociar_necesidad(albergue(), nil)
    end
  end

  describe "a_linea/1 y desde_linea/1" do
    test "guardar y volver a leer da el mismo albergue" do
      {:ok, a} = Albergue.ingresar(albergue(10), "100")
      {:ok, a} = Albergue.ingresar(a, "200")
      {:ok, a} = Albergue.asociar_recurso(a, "R001")
      {:ok, a} = Albergue.asociar_necesidad(a, "N001")

      assert {:ok, leido} = a |> Albergue.a_linea() |> Albergue.desde_linea()
      assert leido == a
    end

    test "un nombre con | se escapa y se recupera" do
      {:ok, a} = Albergue.nuevo("A09", "Norte | Sur", "zona|1", 5)
      assert {:ok, ^a} = a |> Albergue.a_linea() |> Albergue.desde_linea()
    end

    test "un albergue vacío también se recupera" do
      a = albergue()
      assert {:ok, ^a} = a |> Albergue.a_linea() |> Albergue.desde_linea()
    end

    test "tolera saltos de línea al final (Windows)" do
      a = albergue()
      assert {:ok, ^a} = Albergue.desde_linea(Albergue.a_linea(a) <> "\r\n")
    end

    test "las líneas dañadas devuelven error" do
      assert {:error, :linea_invalida} = Albergue.desde_linea("")
      assert {:error, :linea_invalida} = Albergue.desde_linea("A01|Norte|z")
      assert {:error, :linea_invalida} = Albergue.desde_linea("A01|Norte|z|abc|||")
      assert {:error, :linea_invalida} = Albergue.desde_linea("A01|Norte|z|1|1,2||")
      assert {:error, :linea_invalida} = Albergue.desde_linea(nil)
    end
  end

  test "normalizar_codigo/1" do
    assert Albergue.normalizar_codigo(" a01 ") == "A01"
    assert Albergue.normalizar_codigo(5) == nil
  end
end
