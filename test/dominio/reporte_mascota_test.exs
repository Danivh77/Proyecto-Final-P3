defmodule Emergencias.Dominio.ReporteMascotaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.ReporteMascota

  defp reporte(id, tipo, especie, zona, extra \\ []) do
    {:ok, r} =
      ReporteMascota.nuevo(
        id,
        tipo,
        especie,
        Keyword.get(extra, :nombre, "Luna"),
        Keyword.get(extra, :caracteristicas, "collar rojo"),
        Keyword.get(extra, :color, "negra"),
        Keyword.get(extra, :tamano, "mediana"),
        zona,
        "3001112233"
      )

    r
  end

  describe "nuevo/9" do
    test "crea un reporte activo" do
      r = reporte("M001", :perdida, "perro", "zona_norte")
      assert r.estado == :activa
      assert r.coincidencia_con == nil
      assert r.tipo == :perdida
    end

    test "acepta lost/found como tipo" do
      assert %{tipo: :perdida} = reporte("M1", "lost", "perro", "z")
      assert %{tipo: :encontrada} = reporte("M2", "found", "perro", "z")
    end

    test "nombre y características son opcionales" do
      {:ok, r} =
        ReporteMascota.nuevo("M1", :perdida, "perro", nil, nil, "negra", "mediana", "z", "300")

      assert r.nombre == "desconocido"
      assert r.caracteristicas == ""
    end

    test "valida los datos" do
      assert {:error, :tipo_invalido} =
               ReporteMascota.nuevo("M1", "otro", "perro", "L", "", "c", "t", "z", "x")

      assert {:error, :datos_invalidos} =
               ReporteMascota.nuevo("", :perdida, "perro", "L", "", "c", "t", "z", "x")

      assert {:error, :datos_invalidos} =
               ReporteMascota.nuevo("M1", :perdida, "", "L", "", "c", "t", "z", "x")

      assert {:error, :datos_invalidos} =
               ReporteMascota.nuevo("M1", :perdida, "perro", "L", "", "c", "t", "z", "")

      assert {:error, :datos_invalidos} =
               ReporteMascota.nuevo("M1", :perdida, "perro", "L\nx", "", "c", "t", "z", "x")

      assert {:error, :datos_invalidos} =
               ReporteMascota.nuevo("M1", :perdida, "perro", "L", "a\nb", "c", "t", "z", "x")
    end
  end

  describe "marcar_posible/2 y resolver/2" do
    test "marcar_posible guarda con quién podría coincidir" do
      r = reporte("M1", :perdida, "perro", "z")
      assert {:ok, r} = ReporteMascota.marcar_posible(r, "M2")
      assert r.estado == :posible_coincidencia
      assert r.coincidencia_con == "M2"
      assert {:ok, %{coincidencia_con: "M3"}} = ReporteMascota.marcar_posible(r, "M3")
    end

    test "resolver cierra el reporte y no se puede cerrar dos veces" do
      r = reporte("M1", :perdida, "perro", "z")
      assert {:ok, r} = ReporteMascota.resolver(r, "M2")
      assert r.estado == :resuelta
      assert r.coincidencia_con == "M2"
      assert {:error, :ya_resuelto} = ReporteMascota.resolver(r, "M2")
      assert {:error, :ya_resuelto} = ReporteMascota.marcar_posible(r, "M3")
    end

    test "valida el id de la coincidencia" do
      r = reporte("M1", :perdida, "perro", "z")
      assert {:error, :datos_invalidos} = ReporteMascota.resolver(r, "")
      assert {:error, :datos_invalidos} = ReporteMascota.marcar_posible(r, nil)
    end
  end

  describe "filtrar/2" do
    setup do
      reportes = [
        reporte("M1", :perdida, "perro", "zona_norte"),
        reporte("M2", :encontrada, "Perro", "zona_norte"),
        reporte("M3", :perdida, "gato", "centro")
      ]

      {:ok, reportes: reportes}
    end

    test "por especie, zona, estado y tipo", %{reportes: rs} do
      ids = fn lista -> Enum.map(lista, & &1.id) end
      assert ids.(ReporteMascota.filtrar(rs, especie: "perro")) == ["M1", "M2"]
      assert ids.(ReporteMascota.filtrar(rs, zona: "CENTRO")) == ["M3"]
      assert ids.(ReporteMascota.filtrar(rs, estado: "activa")) == ["M1", "M2", "M3"]
      assert ids.(ReporteMascota.filtrar(rs, estado: "resuelta")) == []
      assert ids.(ReporteMascota.filtrar(rs, tipo: "lost")) == ["M1", "M3"]
      assert ids.(ReporteMascota.filtrar(rs, especie: "perro", tipo: :perdida)) == ["M1"]
      assert ids.(ReporteMascota.filtrar(rs, especie: nil, color: "rojo")) == ["M1", "M2", "M3"]
    end
  end

  describe "a_linea/1 y desde_linea/1" do
    test "guardar y volver a leer da el mismo reporte" do
      r = reporte("M1", :perdida, "perro", "zona_norte")
      assert {:ok, ^r} = r |> ReporteMascota.a_linea() |> ReporteMascota.desde_linea()

      {:ok, r} = ReporteMascota.marcar_posible(r, "M2")
      assert {:ok, ^r} = r |> ReporteMascota.a_linea() |> ReporteMascota.desde_linea()

      {:ok, r} = ReporteMascota.resolver(r, "M2")
      assert {:ok, ^r} = r |> ReporteMascota.a_linea() |> ReporteMascota.desde_linea()
    end

    test "características con | se escapan y se recuperan" do
      {:ok, r} =
        ReporteMascota.nuevo(
          "M1",
          :perdida,
          "perro",
          "L|una",
          "collar | rojo",
          "c",
          "t",
          "z",
          "x"
        )

      assert {:ok, ^r} = r |> ReporteMascota.a_linea() |> ReporteMascota.desde_linea()
    end

    test "las líneas dañadas devuelven error" do
      assert {:error, :linea_invalida} = ReporteMascota.desde_linea("")
      assert {:error, :linea_invalida} = ReporteMascota.desde_linea("M1|perdida|perro")

      assert {:error, :linea_invalida} =
               ReporteMascota.desde_linea("M1|rara|perro|L||c|t|z|x|activa|")

      assert {:error, :linea_invalida} =
               ReporteMascota.desde_linea("M1|perdida|perro|L||c|t|z|x|rara|")

      assert {:error, :linea_invalida} = ReporteMascota.desde_linea(nil)
    end
  end
end
