defmodule Emergencias.Dominio.PersonaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Persona

  @fecha "2026-11-15 10:00:00"

  defp persona(id, documento, nombre, zona, estado) do
    {:ok, p} = Persona.nuevo(id, documento, nombre, 30, zona, estado)
    p
  end

  describe "nuevo/6" do
    test "crea una persona con estado inicial :reportada" do
      assert {:ok, p} = Persona.nuevo("P001", "1001", "Andrés Gómez", 34, "zona_norte")
      assert p.estado == :reportada
      assert p.historial == []
      assert p.edad == 34
    end

    test "acepta edad desconocida (nil) y estado inicial como texto" do
      assert {:ok, p} = Persona.nuevo("P001", "1001", "Ana", nil, "centro", "en albergue")
      assert p.edad == nil
      assert p.estado == :en_albergue
    end

    test "valida los datos" do
      assert {:error, :datos_invalidos} = Persona.nuevo("", "1001", "Ana", 3, "centro")
      assert {:error, :datos_invalidos} = Persona.nuevo("P1", "1001", "A|na", 3, "centro")
      assert {:error, :datos_invalidos} = Persona.nuevo("P1", "1001", "Ana", 3, "")
      assert {:error, :documento_invalido} = Persona.nuevo("P1", "", "Ana", 3, "centro")
      assert {:error, :documento_invalido} = Persona.nuevo("P1", "1,2", "Ana", 3, "centro")
      assert {:error, :edad_invalida} = Persona.nuevo("P1", "1001", "Ana", -1, "centro")
      assert {:error, :edad_invalida} = Persona.nuevo("P1", "1001", "Ana", 200, "centro")
      assert {:error, :edad_invalida} = Persona.nuevo("P1", "1001", "Ana", "tres", "centro")

      assert {:error, :estado_invalido} =
               Persona.nuevo("P1", "1001", "Ana", 3, "centro", "volando")
    end
  end

  describe "estados" do
    test "estado_valido?/1 usa guard sobre la lista de estados" do
      assert Persona.estado_valido?(:localizada)
      refute Persona.estado_valido?(:volando)
      refute Persona.estado_valido?("localizada")
    end

    test "estado_desde_texto/1 acepta tildes, mayúsculas y espacios" do
      assert {:ok, :sin_informacion} = Persona.estado_desde_texto("Sin información")
      assert {:ok, :en_albergue} = Persona.estado_desde_texto("en albergue")
      assert {:ok, :en_albergue} = Persona.estado_desde_texto("EN_ALBERGUE")
      assert {:ok, :localizada} = Persona.estado_desde_texto(:localizada)
      assert {:error, :estado_invalido} = Persona.estado_desde_texto("nada")
      assert {:error, :estado_invalido} = Persona.estado_desde_texto(nil)
    end
  end

  describe "transicion/3" do
    test "aplica una transición válida y guarda la fecha en el historial" do
      p = persona("P1", "1", "Ana", "centro", :reportada)
      assert {:ok, p} = Persona.transicion(p, :localizada, @fecha)
      assert p.estado == :localizada
      assert p.historial == [{@fecha, :reportada, :localizada}]

      assert {:ok, p} = Persona.transicion(p, "en albergue", "2026-11-15 11:00:00")
      assert p.estado == :en_albergue

      assert p.historial == [
               {@fecha, :reportada, :localizada},
               {"2026-11-15 11:00:00", :localizada, :en_albergue}
             ]
    end

    test "rechaza transiciones inválidas y no cambia nada" do
      p = persona("P1", "1", "Ana", "centro", :localizada)
      assert {:error, :transicion_invalida} = Persona.transicion(p, :sin_informacion, @fecha)
      assert {:error, :transicion_invalida} = Persona.transicion(p, :localizada, @fecha)
      assert {:error, :transicion_invalida} = Persona.transicion(p, :reportada, @fecha)
    end

    test "reunificada es un estado final" do
      p = persona("P1", "1", "Ana", "centro", :reunificada)

      for destino <- Persona.estados() do
        assert {:error, :transicion_invalida} = Persona.transicion(p, destino, @fecha)
      end
    end

    test "valida el estado destino y la fecha" do
      p = persona("P1", "1", "Ana", "centro", :reportada)
      assert {:error, :estado_invalido} = Persona.transicion(p, "volando", @fecha)
      assert {:error, :fecha_invalida} = Persona.transicion(p, :localizada, "")
      assert {:error, :fecha_invalida} = Persona.transicion(p, :localizada, nil)
      assert {:error, :fecha_invalida} = Persona.transicion(p, :localizada, "a>b")
    end
  end

  describe "buscar/2" do
    setup do
      personas = [
        persona("P1", "1001", "Andrés Gómez", "zona_norte", :en_albergue),
        persona("P2", "1002", "María Rodríguez", "zona_norte", :localizada),
        persona("P3", "1003", "Carlos Gómez", "centro", :reportada),
        persona("P4", "1004", "Lucía Martínez", "centro", :localizada)
      ]

      {:ok, personas: personas}
    end

    defp ids(personas), do: Enum.map(personas, & &1.id)

    test "sin filtros devuelve todas, en el mismo orden", %{personas: ps} do
      assert ids(Persona.buscar(ps, [])) == ["P1", "P2", "P3", "P4"]
    end

    test "por nombre ignora mayúsculas y tildes", %{personas: ps} do
      assert ids(Persona.buscar(ps, nombre: "andres")) == ["P1"]
      assert ids(Persona.buscar(ps, nombre: "GOMEZ")) == ["P1", "P3"]
      assert ids(Persona.buscar(ps, nombre: "rodriguez")) == ["P2"]
    end

    test "por documento, zona y estado", %{personas: ps} do
      assert ids(Persona.buscar(ps, documento: "1003")) == ["P3"]
      assert ids(Persona.buscar(ps, zona: "Centro")) == ["P3", "P4"]
      assert ids(Persona.buscar(ps, estado: "localizada")) == ["P2", "P4"]
      assert ids(Persona.buscar(ps, estado: :en_albergue)) == ["P1"]
    end

    test "combina varios filtros (todos deben cumplirse)", %{personas: ps} do
      assert ids(Persona.buscar(ps, nombre: "gomez", zona: "centro")) == ["P3"]
      assert ids(Persona.buscar(ps, zona: "centro", estado: :localizada)) == ["P4"]
      assert Persona.buscar(ps, nombre: "gomez", estado: :localizada) == []
    end

    test "ignora filtros en nil y claves desconocidas; un estado inválido no coincide", %{
      personas: ps
    } do
      assert length(Persona.buscar(ps, nombre: nil, zona: nil)) == 4
      assert length(Persona.buscar(ps, color: "rojo")) == 4
      assert Persona.buscar(ps, estado: "volando") == []
    end

    test "funciona con mapas y con la lista vacía", %{personas: ps} do
      assert ids(Persona.buscar(ps, %{zona: "centro"})) == ["P3", "P4"]
      assert Persona.buscar([], nombre: "x") == []
    end
  end

  describe "a_linea/1 y desde_linea/1" do
    test "guardar y volver a leer da la misma persona (con historial)" do
      p = persona("P1", "1001", "Andrés Gómez", "zona_norte", :reportada)
      {:ok, p} = Persona.transicion(p, :localizada, @fecha)
      {:ok, p} = Persona.transicion(p, :en_albergue, "2026-11-15 11:00:00")

      assert {:ok, leida} = p |> Persona.a_linea() |> Persona.desde_linea()
      assert leida == p
    end

    test "edad desconocida e historial vacío se recuperan" do
      {:ok, p} = Persona.nuevo("P1", "1001", "Ana", nil, "centro")
      assert {:ok, ^p} = p |> Persona.a_linea() |> Persona.desde_linea()
    end

    test "las líneas dañadas devuelven error" do
      assert {:error, :linea_invalida} = Persona.desde_linea("")
      assert {:error, :linea_invalida} = Persona.desde_linea("P1|1001|Ana")
      assert {:error, :linea_invalida} = Persona.desde_linea("P1|1001|Ana|xx|centro|reportada|")
      assert {:error, :linea_invalida} = Persona.desde_linea("P1|1001|Ana|3|centro|volando|")

      assert {:error, :linea_invalida} =
               Persona.desde_linea("P1|1001|Ana|3|centro|reportada|basura")

      assert {:error, :linea_invalida} = Persona.desde_linea(nil)
    end
  end
end
