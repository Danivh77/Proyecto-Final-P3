defmodule Emergencias.Dominio.RecursoTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.{Movimiento, Recurso}
  import Emergencias.DatosPrueba, only: [recurso_ejemplo: 1]

  test "el inventario inicial puede ser cero, pero no negativo ni fraccionario" do
    assert %Recurso{cantidad: 0} = recurso_ejemplo(0)

    for cantidad <- [-1, 1.5, "2"] do
      assert Recurso.nuevo("R001", "agua", "agua", cantidad, "litros", "centro") ==
               {:error, :cantidad_invalida}
    end
  end

  test "suma entradas y descuenta salidas hasta agotar el inventario" do
    recurso = recurso_ejemplo(50)

    assert {:ok, %Recurso{cantidad: 70} = actualizado} = Recurso.entrada(recurso, 20)
    assert Recurso.puede_cubrir?(actualizado, 70)
    assert {:ok, %Recurso{cantidad: 0}} = Recurso.salida(actualizado, 70)
    assert recurso.cantidad == 50
  end

  test "rechaza salidas sin inventario suficiente" do
    recurso = recurso_ejemplo(50)

    refute Recurso.puede_cubrir?(recurso, 51)
    assert Recurso.salida(recurso, 51) == {:error, :inventario_insuficiente}
  end

  test "las entradas y salidas requieren cantidades enteras positivas" do
    recurso = recurso_ejemplo(50)

    for cantidad <- [-1, 0, 1.5, "2"] do
      assert Recurso.entrada(recurso, cantidad) == {:error, :cantidad_invalida}
      assert Recurso.salida(recurso, cantidad) == {:error, :cantidad_invalida}
      refute Recurso.puede_cubrir?(recurso, cantidad)
    end
  end

  test "recupera el recurso desde texto plano y rechaza líneas dañadas" do
    recurso = %{recurso_ejemplo(50) | nombre: "Agua | potable"}

    assert Recurso.desde_linea(Recurso.a_linea(recurso)) == {:ok, recurso}

    assert Recurso.desde_linea("R001|agua|agua|50 litros|litros|centro") ==
             {:error, :linea_invalida}
  end

  test "recupera los movimientos con la fecha y la referencia originales" do
    for tipo <- ~w(entrada salida asignacion transferencia), referencia <- [nil, "N001|centro"] do
      assert {:ok, %Movimiento{fecha: %NaiveDateTime{}} = movimiento} =
               Movimiento.nuevo(tipo, "R001", 20, referencia, "laura")

      assert Movimiento.desde_linea(Movimiento.a_linea(movimiento)) == {:ok, movimiento}
    end

    assert {:ok, %Movimiento{fecha: ~N[2026-11-14 13:53:00]}} =
             Movimiento.desde_linea("2026-11-14 13:53:00|entrada|R001|20||laura")
  end

  test "rechaza movimientos con fecha, tipo o cantidad inválidos" do
    assert Movimiento.desde_linea("sin fecha|entrada|R001|20||laura") == {:error, :linea_invalida}

    assert Movimiento.nuevo("ajuste", "R001", 20, nil, "laura") ==
             {:error, :tipo_movimiento_invalido}

    assert Movimiento.nuevo("entrada", "R001", -1, nil, "laura") == {:error, :cantidad_invalida}
  end
end
