defmodule Emergencias.ConcurrenciaTest do
  use ExUnit.Case, async: false

  alias Emergencias.Servidores.{InventarioServer, NecesidadServer, ZonaServer}

  setup do
    zona = "zona_" <> Base.encode16(:crypto.strong_rand_bytes(6))
    recurso = "R_" <> zona
    {:ok, _} = ZonaServer.registrar_zona(zona, "Zona de prueba", "alto")
    {:ok, _} = InventarioServer.registrar_recurso(recurso, "agua", "bebidas", 50, "litros", zona)
    %{zona: zona, recurso: recurso}
  end

  test "diez necesidades simultáneas reciben como máximo el saldo disponible", %{
    zona: zona,
    recurso: recurso
  } do
    necesidades = Enum.map(1..10, fn _ -> registrar_necesidad(zona, 10) end)

    resultados =
      en_paralelo(necesidades, fn necesidad ->
        NecesidadServer.asignar_recurso(necesidad.id, recurso, 10, "laura")
      end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 5
    assert Enum.count(resultados, &(&1 == {:error, :inventario_insuficiente})) == 5
    assert [%{cantidad: 0}] = InventarioServer.por_ubicacion(zona)
    assert length(InventarioServer.historial(recurso)) == 5
    assert length(NecesidadServer.listar(zona: zona, estado: "pendiente")) == 5
  end

  test "dos intentos simultáneos sobre la misma necesidad solo descuentan una vez", %{
    zona: zona,
    recurso: recurso
  } do
    necesidad = registrar_necesidad(zona, 20)

    resultados =
      en_paralelo(1..2, fn _ ->
        NecesidadServer.asignar_recurso(necesidad.id, recurso, 20, "laura")
      end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :ya_asignada} in resultados
    assert [%{cantidad: 30}] = InventarioServer.por_ubicacion(zona)
    assert [%{tipo: "asignacion", cantidad: 20}] = InventarioServer.historial(recurso)
  end

  test "las transferencias simultáneas conservan el total", %{zona: zona, recurso: recurso} do
    destino = zona <> "_destino"

    resultados =
      en_paralelo(1..4, fn _ -> InventarioServer.transferir(recurso, zona, destino, 15) end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 3
    assert {:error, :inventario_insuficiente} in resultados
    assert [%{cantidad: 5}] = InventarioServer.por_ubicacion(zona)
    assert [%{cantidad: 45}] = InventarioServer.por_ubicacion(destino)
  end

  defp registrar_necesidad(zona, cantidad) do
    {:ok, necesidad} = NecesidadServer.registrar("agua", cantidad, "alta", zona, "Agua", "laura")
    necesidad
  end

  defp en_paralelo(elementos, operacion) do
    tareas =
      Enum.map(elementos, fn elemento ->
        Task.async(fn ->
          receive do
            :iniciar -> operacion.(elemento)
          end
        end)
      end)

    Enum.each(tareas, &send(&1.pid, :iniciar))
    Task.await_many(tareas)
  end
end
