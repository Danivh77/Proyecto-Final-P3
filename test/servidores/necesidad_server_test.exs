defmodule Emergencias.Servidores.NecesidadServerTest do
  use ExUnit.Case, async: false

  alias Emergencias.Servidores.{
    AlbergueServer,
    AlbergueSupervisor,
    InventarioServer,
    NecesidadServer,
    ZonaServer
  }

  setup do
    zona = "zona_" <> Base.encode16(:crypto.strong_rand_bytes(6))
    recurso = "R_" <> zona
    {:ok, _} = ZonaServer.registrar_zona(zona, "Zona de prueba", "alto")
    {:ok, _} = InventarioServer.registrar_recurso(recurso, "agua", "bebidas", 50, "litros", zona)
    %{zona: zona, recurso: recurso}
  end

  test "lista pendientes por prioridad y filtra por albergue", %{zona: zona} do
    codigo = "A_" <> zona
    {:ok, albergue} = AlbergueSupervisor.crear_albergue(codigo, "Albergue de prueba", zona, 20)
    {:ok, baja} = NecesidadServer.registrar("agua", 25, "baja", zona, "Agua", "laura")

    {:ok, critica} =
      NecesidadServer.registrar("agua", 30, "critica", zona, "Agua", "laura", " #{codigo} ")

    assert critica.albergue == albergue.codigo
    assert NecesidadServer.listar(zona: zona, estado: "pendiente") == [critica, baja]
    assert NecesidadServer.por_albergue(codigo) == [critica]

    assert NecesidadServer.registrar(
             "agua",
             30,
             "alta",
             zona,
             "Agua",
             "laura",
             codigo <> "_ausente"
           ) ==
             {:error, :albergue_no_encontrado}

    assert NecesidadServer.registrar("agua", 30, "alta", zona, "Agua", "laura", " ") ==
             {:error, :albergue_invalido}

    assert NecesidadServer.registrar("agua", 30, "alta", zona <> "_ausente", "Agua", "laura") ==
             {:error, :zona_no_encontrada}
  end

  test "la consulta de albergue incluye las asociaciones del inventario y las necesidades", %{
    zona: zona,
    recurso: recurso
  } do
    codigo = "A_" <> zona
    {:ok, albergue} = AlbergueSupervisor.crear_albergue(codigo, "Albergue de prueba", zona, 20)

    {:ok, necesidad} =
      NecesidadServer.registrar("agua", 30, "alta", zona, "Agua", "laura", codigo)

    {:ok, _} = InventarioServer.transferir(recurso, zona, albergue.codigo, 40)

    assert {:ok, %{recursos: [^recurso], necesidades: [id]}} =
             AlbergueServer.consultar(" #{codigo} ")

    assert id == necesidad.id
  end

  test "revierte la reserva cuando el inventario rechaza el descuento", %{
    zona: zona,
    recurso: recurso
  } do
    {:ok, necesidad} = NecesidadServer.registrar("agua", 60, "alta", zona, "Agua", "laura")

    assert NecesidadServer.asignar_recurso(necesidad.id, recurso, 60, "laura") ==
             {:error, :inventario_insuficiente}

    assert {:ok,
            %{estado: "pendiente", asignaciones: [], historial: [{"asignada", "pendiente"} | _]}} =
             NecesidadServer.obtener(necesidad.id)

    assert [%{cantidad: 50}] = InventarioServer.por_ubicacion(zona)
    assert InventarioServer.historial(recurso) == []
  end

  test "una necesidad atendida no vuelve a consumir recursos", %{zona: zona, recurso: recurso} do
    {:ok, necesidad} = NecesidadServer.registrar("agua", 30, "alta", zona, "Agua", "laura")
    id = necesidad.id

    assert {:ok, %{estado: "asignada", asignaciones: [{^recurso, ^zona, 30}]}} =
             NecesidadServer.asignar_recurso(id, "agua", 30, "laura")

    assert {:ok, _} = NecesidadServer.cambiar_estado(id, "en_atencion")
    assert {:ok, %{estado: "atendida"}} = NecesidadServer.cambiar_estado(id, "atendida")
    assert {:error, :ya_resuelto} = NecesidadServer.asignar_recurso(id, recurso, 10, "laura")
    assert [%{cantidad: 20}] = InventarioServer.por_ubicacion(zona)
    assert [%{tipo: "asignacion", cantidad: 30}] = InventarioServer.historial(recurso)
  end
end
