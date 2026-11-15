defmodule Emergencias.Dominio.NecesidadTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Necesidad
  import Emergencias.DatosPrueba, only: [necesidad_ejemplo: 1]

  test "crea una solicitud pendiente con la forma canónica de la prioridad" do
    assert %Necesidad{estado: "pendiente", prioridad: "critica", asignaciones: [], historial: []} =
             necesidad_ejemplo("crítica")

    assert Necesidad.tipo_valido?("primeros_auxilios")
    assert Necesidad.prioridad_valida?("crítica")
    refute Necesidad.prioridad_valida?("urgente")
  end

  test "rechaza tipos, prioridades y cantidades inválidos" do
    assert Necesidad.nuevo("N001", "inventado", "Agua potable", 30, "centro", "alta", "laura") ==
             {:error, :tipo_necesidad_invalido}

    assert Necesidad.nuevo("N001", "agua", "Agua potable", 30, "centro", "urgente", "laura") ==
             {:error, :prioridad_invalida}

    for cantidad <- [0, -1, 2.5, "30"] do
      assert Necesidad.nuevo("N001", "agua", "Agua potable", cantidad, "centro", "alta", "laura") ==
               {:error, :cantidad_invalida}
    end
  end

  test "registra las transiciones válidas y protege los estados finales" do
    pendiente = necesidad_ejemplo("alta")
    assert {:ok, asignada} = Necesidad.transicion(pendiente, "asignada")
    assert {:ok, en_atencion} = Necesidad.transicion(asignada, "en_atencion")

    assert {:ok, %Necesidad{estado: "atendida"} = atendida} =
             Necesidad.transicion(en_atencion, "atendida")

    assert atendida.historial == [
             {"en_atencion", "atendida"},
             {"asignada", "en_atencion"},
             {"pendiente", "asignada"}
           ]

    assert {:error, :transicion_invalida} = Necesidad.transicion(pendiente, "atendida")
    assert {:error, :transicion_invalida} = Necesidad.transicion(asignada, "asignada")
    assert {:error, :transicion_invalida} = Necesidad.transicion(atendida, "asignada")

    assert {:ok, cancelada} = Necesidad.transicion(pendiente, "cancelada")
    assert {:error, :transicion_invalida} = Necesidad.transicion(cancelada, "pendiente")
  end

  test "revierte una reserva antes de confirmar recursos" do
    assert {:ok, asignada} = Necesidad.transicion(necesidad_ejemplo("alta"), "asignada")
    assert {:ok, %Necesidad{estado: "pendiente"}} = Necesidad.transicion(asignada, "pendiente")

    con_recursos = %{asignada | asignaciones: [{"R001", "centro_acopio_1", 10}]}
    assert {:error, :transicion_invalida} = Necesidad.transicion(con_recursos, "pendiente")
  end

  test "ordena por prioridad y conserva el orden de entrada en los empates" do
    baja = necesidad_ejemplo("baja")
    alta = necesidad_ejemplo("alta")
    alta_siguiente = %{alta | id: "N002"}
    critica = necesidad_ejemplo("critica")
    media = necesidad_ejemplo("media")

    assert Enum.map(~w(critica alta media baja), &Necesidad.valor_prioridad/1) == [4, 3, 2, 1]

    assert Necesidad.insertar_por_prioridad(alta_siguiente, [critica, alta, baja]) ==
             [critica, alta, alta_siguiente, baja]

    assert Necesidad.ordenar_por_prioridad([baja, alta, critica, alta_siguiente, media]) ==
             [critica, alta, alta_siguiente, media, baja]
  end

  test "combina los filtros de zona, tipo, prioridad y estado" do
    pendiente = necesidad_ejemplo("critica")
    sur = %{pendiente | zona: "sur"}
    alimentos = %{pendiente | tipo: "alimentos"}
    alta = necesidad_ejemplo("alta")
    {:ok, asignada} = Necesidad.transicion(pendiente, "asignada")
    necesidades = [sur, alimentos, pendiente, alta, asignada]

    assert Necesidad.filtrar(necesidades,
             zona: "centro",
             tipo: "agua",
             prioridad: "crítica",
             estado: "pendiente"
           ) == [pendiente]

    assert Necesidad.filtrar(necesidades, []) == necesidades
    assert Necesidad.filtrar(necesidades, zona: "ausente") == []
  end

  test "recupera la solicitud completa desde una línea de texto" do
    pendiente = necesidad_ejemplo("critica")
    assert Necesidad.desde_linea(Necesidad.a_linea(pendiente)) == {:ok, pendiente}

    {:ok, asignada} = Necesidad.transicion(pendiente, "asignada")
    {:ok, en_atencion} = Necesidad.transicion(asignada, "en_atencion")

    necesidad = %{
      en_atencion
      | descripcion: "Agua | recepción\nPuesto sur",
        albergue: "A01",
        asignaciones: [{"R001", "Bodega | Norte", 10}, {"R002", "Puesto sur", 20}]
    }

    linea = Necesidad.a_linea(necesidad)
    refute String.contains?(linea, "\n")
    assert Necesidad.desde_linea(linea) == {:ok, necesidad}
    assert Necesidad.desde_linea("N001|agua|sin campos") == {:error, :linea_invalida}
  end
end
