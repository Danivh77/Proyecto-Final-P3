defmodule Emergencias.PersistenciaTest do
  use ExUnit.Case, async: false

  alias Emergencias.Persistencia
  import Emergencias.DatosPrueba

  defp a_linea(%{codigo: codigo, nombre: nombre, cantidad: cantidad}) do
    Persistencia.unir_campos([codigo, nombre, cantidad])
  end

  defp desde_linea(linea) do
    case Persistencia.separar_campos(linea) do
      [codigo, nombre, cantidad] ->
        case Integer.parse(cantidad) do
          {numero, ""} -> {:ok, %{codigo: codigo, nombre: nombre, cantidad: numero}}
          _ -> {:error, :cantidad_invalida}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  setup do
    limpiar_datos()
    :ok
  end

  test "usa la carpeta data_test en las pruebas" do
    assert Persistencia.carpeta_datos() == "data_test"
    assert Persistencia.ruta("recursos.txt") == "data_test/recursos.txt"
  end

  test "cargar un archivo que no existe devuelve una lista vacía" do
    assert Persistencia.cargar("no_existe.txt", &desde_linea/1) == {:ok, []}
  end

  test "lo que se guarda se vuelve a cargar igual" do
    recursos = [
      %{codigo: "R001", nombre: "agua", cantidad: 50},
      %{codigo: "R002", nombre: "arroz", cantidad: 120}
    ]

    assert Persistencia.guardar("recursos.txt", recursos, &a_linea/1) == :ok
    assert Persistencia.cargar("recursos.txt", &desde_linea/1) == {:ok, recursos}
  end

  test "guardar reemplaza el contenido anterior" do
    Persistencia.guardar(
      "recursos.txt",
      [%{codigo: "R001", nombre: "agua", cantidad: 50}],
      &a_linea/1
    )

    Persistencia.guardar(
      "recursos.txt",
      [%{codigo: "R001", nombre: "agua", cantidad: 20}],
      &a_linea/1
    )

    assert {:ok, [%{cantidad: 20}]} = Persistencia.cargar("recursos.txt", &desde_linea/1)
  end

  test "las líneas vacías o dañadas se ignoran al cargar" do
    File.write!(
      Persistencia.ruta("recursos.txt"),
      "R001|agua|50\n\nlinea dañada\nR002|arroz|no_es_numero\n"
    )

    assert {:ok, [%{codigo: "R001"}]} = Persistencia.cargar("recursos.txt", &desde_linea/1)
  end

  test "agregar_linea conserva lo que ya había" do
    Persistencia.agregar_linea("actividad.log", "laura|connect")
    Persistencia.agregar_linea("actividad.log", "laura|summary")

    assert File.read!(Persistencia.ruta("actividad.log")) == "laura|connect\nlaura|summary\n"
  end

  test "guardar crea las subcarpetas que hagan falta" do
    assert Persistencia.guardar(
             "albergues/A01.txt",
             [%{codigo: "A01", nombre: "Norte", cantidad: 150}],
             &a_linea/1
           ) == :ok

    assert Persistencia.listar_archivos("albergues") == ["albergues/A01.txt"]
  end

  test "los textos con | y saltos de línea no dañan el archivo" do
    campos = ["MSG001", "Estoy bien | en el albergue\nnorte", "ruta\\con\\barras", ""]

    linea = Persistencia.unir_campos(campos)

    refute String.contains?(linea, "\n")
    assert Persistencia.separar_campos(linea) == campos
  end

  test "nil se guarda como texto vacío" do
    assert Persistencia.unir_campos(["P001", nil, "centro"]) == "P001||centro"
  end
end
