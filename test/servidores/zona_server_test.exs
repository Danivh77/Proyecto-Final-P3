defmodule Emergencias.Servidores.ZonaServerTest do
  use ExUnit.Case, async: false

  alias Emergencias.Servidores.{InventarioServer, NecesidadServer, ZonaServer}

  test "el estado incluye recursos y pendientes del árbol consultado" do
    sufijo = Base.encode16(:crypto.strong_rand_bytes(6))
    zona = "zona_" <> sufijo
    sector = "sector_" <> sufijo
    punto = "punto_" <> sufijo
    externa = "externa_" <> sufijo
    codigo_raiz = "R_raiz_" <> sufijo
    codigo_punto = "R_punto_" <> sufijo
    codigo_externo = "R_externo_" <> sufijo

    assert {:ok, _} = ZonaServer.registrar_zona(zona, "Zona", "alto")
    assert {:ok, _} = ZonaServer.registrar_sector(zona, sector, "Sector")
    assert {:ok, _} = ZonaServer.registrar_punto(sector, punto, "Punto")
    assert {:ok, _} = ZonaServer.registrar_zona(externa, "Otra zona", "medio")

    assert {:ok, recurso_raiz} =
             InventarioServer.registrar_recurso(
               codigo_raiz,
               "agua",
               "bebidas",
               10,
               "litros",
               zona
             )

    assert {:ok, recurso_punto} =
             InventarioServer.registrar_recurso(
               codigo_punto,
               "agua",
               "bebidas",
               5,
               "litros",
               punto
             )

    assert {:ok, _} =
             InventarioServer.registrar_recurso(
               codigo_externo,
               "agua",
               "bebidas",
               3,
               "litros",
               externa
             )

    assert {:ok, pendiente_raiz} =
             NecesidadServer.registrar("agua", 4, "baja", zona, "Zona", "laura")

    assert {:ok, pendiente_punto} =
             NecesidadServer.registrar("agua", 3, "critica", punto, "Punto", "laura")

    assert {:ok, cancelada} =
             NecesidadServer.registrar("agua", 2, "alta", sector, "Sector", "laura")

    assert {:ok, _} = NecesidadServer.cambiar_estado(cancelada.id, "cancelada")
    assert {:ok, _} = NecesidadServer.registrar("agua", 2, "alta", externa, "Otra zona", "laura")

    assert {:ok, estado} = ZonaServer.estado_zona(zona)
    assert estado.sectores == 1
    assert estado.puntos == 1
    assert MapSet.new(estado.recursos) == MapSet.new([recurso_raiz, recurso_punto])
    assert estado.necesidades_pendientes == [pendiente_punto, pendiente_raiz]

    assert {:ok, %{recursos: [^recurso_punto], necesidades_pendientes: [^pendiente_punto]}} =
             ZonaServer.estado_zona(sector)

    assert {:error, :no_encontrado} = ZonaServer.estado_zona(zona <> "_ausente")
  end
end
