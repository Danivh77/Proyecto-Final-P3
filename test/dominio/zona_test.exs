defmodule Emergencias.Dominio.ZonaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Zona
  import Emergencias.DatosPrueba, only: [zona_ejemplo: 0]
  require Zona

  setup do
    %Zona{hijos: [_, %Zona{hijos: [punto]}]} = arbol = zona_ejemplo()
    %{arbol: arbol, punto: punto}
  end

  test "valida los datos del nodo y acepta cero personas afectadas" do
    assert {:ok, %Zona{hijos: [], personas_afectadas: 0}} =
             Zona.nuevo("p02", "Puesto", "punto", "bajo", 0)

    assert match?(nivel when Zona.nivel_valido?(nivel), "critico")
    assert Zona.nuevo("", "Puesto", "punto", "bajo", 0) == {:error, :codigo_invalido}
    assert Zona.nuevo("p02", " ", "punto", "bajo", 0) == {:error, :nombre_invalido}
    assert Zona.nuevo("p02", "Puesto", "barrio", "bajo", 0) == {:error, :tipo_invalido}
    assert Zona.nuevo("p02", "Puesto", "punto", "urgente", 0) == {:error, :nivel_invalido}

    assert Zona.nuevo("p02", "Puesto", "punto", "bajo", -1) ==
             {:error, :personas_afectadas_invalidas}
  end

  test "acumula personas, sectores y puntos de los tres niveles", %{arbol: arbol, punto: punto} do
    assert Zona.estadisticas(arbol) == %{personas_afectadas: 155, sectores: 2, puntos: 1}
    assert Zona.estadisticas(punto) == %{personas_afectadas: 5, sectores: 0, puntos: 1}
  end

  test "encuentra la raíz y los nodos anidados, y avisa si no existe el código", %{
    arbol: arbol,
    punto: punto
  } do
    assert Zona.buscar_nodo(arbol, "centro") == {:ok, arbol}
    assert {:ok, %Zona{tipo: "sector", hijos: [^punto]}} = Zona.buscar_nodo(arbol, "sur")
    assert Zona.buscar_nodo(arbol, "p01") == {:ok, punto}
    assert Zona.buscar_nodo(arbol, "ausente") == {:error, :no_encontrado}
    assert Zona.listar_codigos(arbol) == ["centro", "norte", "sur", "p01"]
  end

  test "rechaza padres inexistentes, niveles fuera de orden y códigos duplicados", %{
    arbol: arbol
  } do
    {:ok, punto} = Zona.nuevo("p02", "Puesto Norte", "punto", "bajo", 1)
    {:ok, duplicado} = Zona.nuevo("p01", "Puesto Norte", "punto", "bajo", 1)

    assert Zona.agregar_hijo(arbol, "ausente", punto) == {:error, :no_encontrado}
    assert Zona.agregar_hijo(arbol, "centro", punto) == {:error, :jerarquia_invalida}
    assert Zona.agregar_hijo(arbol, "p01", punto) == {:error, :jerarquia_invalida}
    assert Zona.agregar_hijo(arbol, "norte", duplicado) == {:error, :id_duplicado}

    assert {:ok, actualizado} = Zona.agregar_hijo(arbol, "norte", punto)
    assert Zona.buscar_nodo(actualizado, "p02") == {:ok, punto}
    assert Zona.buscar_nodo(arbol, "p02") == {:error, :no_encontrado}
  end

  test "recupera el árbol entero desde una sola línea de texto", %{arbol: arbol} do
    linea = Zona.a_linea(arbol)
    refute String.contains?(linea, "\n")
    assert Zona.desde_linea(linea) == {:ok, arbol}
  end

  test "rechaza líneas incompletas o con un árbol inválido" do
    assert Zona.desde_linea("centro|Centro|zona|alto|100|1") == {:error, :linea_invalida}

    assert Zona.desde_linea("centro|Centro|zona|alto|100|1|p01|Puesto|punto|bajo|5|0") ==
             {:error, :linea_invalida}

    assert Zona.desde_linea("centro|Centro|zona|alto|100|1|centro|Sector|sector|bajo|5|0") ==
             {:error, :linea_invalida}
  end
end
