defmodule Emergencias.Dominio.MatchingTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.{Matching, ReporteMascota}

  defp reporte(id, tipo, especie, zona, color, tamano, caracteristicas) do
    {:ok, r} =
      ReporteMascota.nuevo(id, tipo, especie, "x", caracteristicas, color, tamano, zona, "300")

    r
  end

  describe "puntaje/2" do
    test "especie distinta da 0 aunque todo lo demás coincida" do
      a = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "collar rojo")
      b = reporte("M2", :encontrada, "gato", "norte", "negra", "mediana", "collar rojo")
      assert Matching.puntaje(a, b) == 0
    end

    test "misma especie sin más coincidencias da 0" do
      a = reporte("M1", :perdida, "perro", "norte", "negra", "grande", "")
      b = reporte("M2", :encontrada, "perro", "sur", "blanca", "pequeña", "")
      assert Matching.puntaje(a, b) == 0
    end

    test "suma zona 30, color 25 y tamaño 20" do
      base = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "")

      solo_zona = reporte("M2", :encontrada, "perro", "norte", "blanca", "grande", "")
      solo_color = reporte("M3", :encontrada, "perro", "sur", "negra", "grande", "")
      solo_tamano = reporte("M4", :encontrada, "perro", "sur", "blanca", "mediana", "")
      todo = reporte("M5", :encontrada, "perro", "norte", "negra", "mediana", "")

      assert Matching.puntaje(base, solo_zona) == 30
      assert Matching.puntaje(base, solo_color) == 25
      assert Matching.puntaje(base, solo_tamano) == 20
      assert Matching.puntaje(base, todo) == 75
    end

    test "cada palabra en común de las características suma 5, hasta 25" do
      base =
        reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "collar rojo orejas caidas")

      dos =
        reporte("M2", :encontrada, "perro", "sur", "blanca", "grande", "tiene collar y orejas")

      todas =
        reporte(
          "M3",
          :encontrada,
          "perro",
          "sur",
          "blanca",
          "grande",
          "collar rojo orejas caidas"
        )

      muchas =
        reporte(
          "M4",
          :perdida,
          "perro",
          "sur",
          "blanca",
          "grande",
          "uno dos tres cuatro cinco seis siete"
        )

      # Misma especie pero zona, color y tamaño distintos: solo cuentan las características.
      muchas_b =
        reporte(
          "M5",
          :encontrada,
          "perro",
          "norte",
          "negra",
          "pequeña",
          "uno dos tres cuatro cinco seis siete"
        )

      assert Matching.puntaje(base, dos) == 10
      assert Matching.puntaje(base, todas) == 20
      assert Matching.puntaje(muchas, muchas_b) == 25
    end

    test "el máximo posible es 100 y es simétrico" do
      a = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "a1b b2c c3d d4e e5f f6g")

      b =
        reporte(
          "M2",
          :encontrada,
          "perro",
          "norte",
          "negra",
          "mediana",
          "a1b b2c c3d d4e e5f f6g"
        )

      assert Matching.puntaje(a, b) == 100
      assert Matching.puntaje(a, b) == Matching.puntaje(b, a)
    end

    test "ignora mayúsculas y tildes" do
      a = reporte("M1", :perdida, "Perro", "Zona_Norte", "NEGRA", "Pequeña", "")
      b = reporte("M2", :encontrada, "perro", "zona_norte", "negra", "pequena", "")
      assert Matching.puntaje(a, b) == 75
    end
  end

  describe "palabras_comunes/2" do
    test "devuelve las palabras compartidas, ordenadas y sin repetir" do
      assert Matching.palabras_comunes("Collar ROJO, orejas caídas", "rojo collar caidas rojo") ==
               ["caidas", "collar", "rojo"]
    end

    test "ignora palabras cortas y de relleno" do
      assert Matching.palabras_comunes("con un collar de la", "con un collar de la") == ["collar"]
    end

    test "maneja nil y vacío" do
      assert Matching.palabras_comunes(nil, "collar") == []
      assert Matching.palabras_comunes("", "") == []
    end
  end

  describe "candidatos/2" do
    test "solo reportes del tipo contrario, misma especie y abiertos" do
      perdida = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "")
      encontrada = reporte("M2", :encontrada, "perro", "norte", "negra", "mediana", "")
      otra_especie = reporte("M3", :encontrada, "gato", "norte", "negra", "mediana", "")
      mismo_tipo = reporte("M4", :perdida, "perro", "norte", "negra", "mediana", "")

      {:ok, cerrada} =
        ReporteMascota.resolver(reporte("M5", :encontrada, "perro", "n", "c", "t", ""), "M9")

      {:ok, posible} =
        ReporteMascota.marcar_posible(
          reporte("M6", :encontrada, "perro", "n", "c", "t", ""),
          "M8"
        )

      todos = [perdida, encontrada, otra_especie, mismo_tipo, cerrada, posible]

      assert perdida |> Matching.candidatos(todos) |> Enum.map(& &1.id) == ["M2", "M6"]
      assert Matching.candidatos(encontrada, todos) |> Enum.map(& &1.id) == ["M1", "M4"]
    end
  end

  describe "mejor_coincidencia/3" do
    test "elige el candidato de mayor puntaje si alcanza el umbral" do
      perdida = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "collar rojo")
      regular = reporte("M2", :encontrada, "perro", "norte", "blanca", "grande", "")
      buena = reporte("M3", :encontrada, "perro", "norte", "negra", "mediana", "collar rojo")
      mala = reporte("M4", :encontrada, "perro", "sur", "blanca", "grande", "")

      assert {:ok, {elegida, 85}} = Matching.mejor_coincidencia(perdida, [regular, buena, mala])
      assert elegida.id == "M3"
    end

    test "si ninguno llega a 60 devuelve :sin_coincidencia" do
      perdida = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "")
      debil = reporte("M2", :encontrada, "perro", "norte", "blanca", "grande", "")
      assert Matching.puntaje(perdida, debil) < Matching.umbral()
      assert {:error, :sin_coincidencia} = Matching.mejor_coincidencia(perdida, [debil])
      assert {:error, :sin_coincidencia} = Matching.mejor_coincidencia(perdida, [])
    end

    test "el umbral es inclusivo (60 cuenta)" do
      perdida = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "")
      justo = reporte("M2", :encontrada, "perro", "norte", "negra", "grande", "")
      assert Matching.puntaje(perdida, justo) == 55

      justo = reporte("M3", :encontrada, "perro", "norte", "negra", "mediana", "")
      assert {:ok, {_, 75}} = Matching.mejor_coincidencia(perdida, [justo])
    end

    test "en caso de empate se queda con el primero" do
      perdida = reporte("M1", :perdida, "perro", "norte", "negra", "mediana", "")
      a = reporte("M2", :encontrada, "perro", "norte", "negra", "mediana", "")
      b = reporte("M3", :encontrada, "perro", "norte", "negra", "mediana", "")
      assert {:ok, {elegida, _}} = Matching.mejor_coincidencia(perdida, [a, b])
      assert elegida.id == "M2"
    end
  end

  test "umbral/0 es 60" do
    assert Matching.umbral() == 60
  end
end
