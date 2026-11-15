defmodule Emergencias.Servidores.InventarioServerTest do
  use ExUnit.Case, async: false

  alias Emergencias.Dominio.{Movimiento, Recurso}
  alias Emergencias.Servidores.InventarioServer

  setup do
    codigo = "R" <> Base.encode16(:crypto.strong_rand_bytes(6))
    origen = codigo <> "_origen"
    destino = codigo <> "_destino"

    assert {:ok, %Recurso{cantidad: 50}} =
             InventarioServer.registrar_recurso(codigo, "agua", "bebida", 50, "litros", origen)

    %{codigo: codigo, origen: origen, destino: destino}
  end

  test "rechaza el registro duplicado y conserva el historial de entradas y salidas", contexto do
    %{codigo: codigo, origen: origen, destino: destino} = contexto

    assert {:error, :id_duplicado} =
             InventarioServer.registrar_recurso(codigo, "agua", "bebida", 1, "litros", destino)

    assert {:ok, %Recurso{cantidad: 60}} = InventarioServer.entrada(codigo, 10, "laura")
    assert {:ok, %Recurso{cantidad: 55}} = InventarioServer.salida(codigo, 5, "laura")

    assert [
             %Movimiento{tipo: "salida", cantidad: 5, referencia: ^origen},
             %Movimiento{tipo: "entrada", cantidad: 10}
           ] = InventarioServer.historial(codigo)
  end

  test "transfiere a un destino nuevo y acumula en el mismo destino en la siguiente operación",
       contexto do
    %{codigo: codigo, origen: origen, destino: destino} = contexto

    assert {:ok, %Recurso{cantidad: 20}} =
             InventarioServer.transferir(codigo, origen, destino, 20)

    assert {:ok, %Recurso{cantidad: 25}} = InventarioServer.transferir(codigo, origen, destino, 5)

    assert {:error, :inventario_insuficiente} =
             InventarioServer.transferir(codigo, origen, destino, 26)

    assert {:error, :ubicacion_requerida} = InventarioServer.entrada(codigo, 1, "laura")
    assert [%Recurso{cantidad: 25}] = InventarioServer.por_ubicacion(origen)
    assert [%Recurso{cantidad: 25}] = InventarioServer.por_ubicacion(destino)

    assert [%Movimiento{tipo: "transferencia"}, %Movimiento{tipo: "transferencia"}] =
             InventarioServer.historial(codigo)
  end

  test "solo un descuento simultáneo puede consumir las últimas unidades", contexto do
    %{codigo: codigo, origen: origen} = contexto

    resultados =
      [30, 25]
      |> Task.async_stream(fn cantidad ->
        InventarioServer.descontar({codigo, origen}, cantidad, "N#{cantidad}", "laura")
      end)
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert [{:ok, %Recurso{cantidad: restante}}] =
             Enum.filter(resultados, &match?({:ok, _}, &1))

    assert {:error, :inventario_insuficiente} in resultados

    assert [%Movimiento{tipo: "asignacion", cantidad: asignada}] =
             InventarioServer.historial(codigo)

    assert restante == 50 - asignada
    assert [%Recurso{cantidad: ^restante}] = InventarioServer.por_ubicacion(origen)
  end
end
