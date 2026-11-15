defmodule Emergencias.Servidores.FamiliaServerTest do
  # No es async: usa el FamiliaServer único del sistema y la carpeta data_test.
  use ExUnit.Case, async: false

  alias Emergencias.DatosPrueba
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.FamiliaServer

  setup do
    DatosPrueba.limpiar_datos()
    reiniciar()
    :ok
  end

  # Reinicia el servidor para que vuelva a cargar los archivos de data_test.
  defp reiniciar do
    :ok = Supervisor.terminate_child(Emergencias.Supervisor, FamiliaServer)
    {:ok, _} = Supervisor.restart_child(Emergencias.Supervisor, FamiliaServer)
    :ok
  end

  defp reportar(extra \\ %{}) do
    d = Map.merge(DatosPrueba.persona_ejemplo(), extra)
    FamiliaServer.reportar_persona(d.documento, d.nombre, d.edad, d.zona, d.estado)
  end

  describe "reportar_persona/5 y buscar/1" do
    test "registra una persona con id P001 y estado inicial" do
      assert {:ok, p} = reportar()
      assert p.id == "P001"
      assert p.estado == :localizada
      assert {:ok, ^p} = FamiliaServer.buscar("1001234567")
      assert {:ok, ^p} = FamiliaServer.buscar("  1001234567 ")
    end

    test "los ids son consecutivos" do
      {:ok, a} = reportar(%{documento: "1"})
      {:ok, b} = reportar(%{documento: "2"})
      {:ok, c} = reportar(%{documento: "3"})
      assert [a.id, b.id, c.id] == ["P001", "P002", "P003"]
    end

    test "rechaza un documento repetido" do
      assert {:ok, _} = reportar()
      assert {:error, :persona_ya_registrada} = reportar(%{nombre: "Otro nombre"})
      assert {:ok, %{personas_registradas: 1}} = {:ok, FamiliaServer.resumen()}
    end

    test "valida los datos antes de cambiar el estado" do
      assert {:error, :documento_invalido} = reportar(%{documento: ""})
      assert {:error, :datos_invalidos} = reportar(%{nombre: ""})
      assert {:error, :edad_invalida} = reportar(%{edad: -3})
      assert {:error, :estado_invalido} = reportar(%{estado: "volando"})
      assert %{personas_registradas: 0} = FamiliaServer.resumen()
    end

    test "buscar un documento inexistente da error" do
      assert {:error, :persona_no_encontrada} = FamiliaServer.buscar("999")
      assert {:error, :persona_no_encontrada} = FamiliaServer.buscar(nil)
    end

    test "el estado por defecto es :reportada" do
      assert {:ok, p} = FamiliaServer.reportar_persona("55", "Ana", nil, "centro")
      assert p.estado == :reportada
      assert p.edad == nil
    end
  end

  describe "buscar_por/1" do
    setup do
      {:ok, _} = reportar(%{documento: "1", nombre: "Andrés Gómez", zona: "zona_norte"})

      {:ok, _} =
        reportar(%{documento: "2", nombre: "María Gómez", zona: "centro", estado: "reportada"})

      {:ok, _} = reportar(%{documento: "3", nombre: "Carlos Pérez", zona: "centro"})
      :ok
    end

    test "filtra por nombre, zona y estado" do
      assert {:ok, lista} = FamiliaServer.buscar_por(nombre: "gomez")
      assert Enum.map(lista, & &1.documento) == ["1", "2"]

      assert {:ok, lista} = FamiliaServer.buscar_por(zona: "centro", estado: "localizada")
      assert Enum.map(lista, & &1.documento) == ["3"]

      assert {:ok, lista} = FamiliaServer.buscar_por(documento: "2")
      assert [%{nombre: "María Gómez"}] = lista
    end

    test "sin filtros devuelve todas y con filtros que no coinciden devuelve vacío" do
      assert {:ok, lista} = FamiliaServer.buscar_por()
      assert length(lista) == 3
      assert {:ok, []} = FamiliaServer.buscar_por(nombre: "zzz")
    end

    test "rechaza filtros que no son lista ni mapa" do
      assert {:error, :filtros_invalidos} = FamiliaServer.buscar_por("zona=centro")
    end
  end

  describe "cambiar_estado/3 e historial/1" do
    test "aplica transiciones válidas y registra el historial con fecha" do
      {:ok, _} = reportar(%{estado: "reportada"})
      assert {:ok, p} = FamiliaServer.cambiar_estado("1001234567", "localizada", "laura")
      assert p.estado == :localizada
      assert {:ok, _} = FamiliaServer.cambiar_estado("1001234567", :en_albergue)

      assert {:ok, [primero, segundo]} = FamiliaServer.historial("1001234567")
      assert %{de: :reportada, a: :localizada} = primero
      assert %{de: :localizada, a: :en_albergue} = segundo
      assert primero.fecha =~ ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/
    end

    test "rechaza transiciones inválidas sin cambiar nada" do
      {:ok, _} = reportar(%{estado: "localizada"})

      assert {:error, :transicion_invalida} =
               FamiliaServer.cambiar_estado("1001234567", :sin_informacion)

      assert {:error, :transicion_invalida} =
               FamiliaServer.cambiar_estado("1001234567", :localizada)

      assert {:error, :estado_invalido} = FamiliaServer.cambiar_estado("1001234567", "volando")
      assert {:ok, %{estado: :localizada}} = FamiliaServer.buscar("1001234567")
      assert {:ok, []} = FamiliaServer.historial("1001234567")
    end

    test "persona inexistente" do
      assert {:error, :persona_no_encontrada} = FamiliaServer.cambiar_estado("999", :localizada)
      assert {:error, :persona_no_encontrada} = FamiliaServer.historial("999")
    end

    test "una persona reunificada ya no cambia de estado" do
      {:ok, _} = reportar(%{estado: "reunificada"})

      assert {:error, :transicion_invalida} =
               FamiliaServer.cambiar_estado("1001234567", :localizada)
    end
  end

  describe "mensajes" do
    test "enviar, listar y marcar como entregado o pendiente" do
      assert {:ok, m1} =
               FamiliaServer.enviar_mensaje(
                 "ana",
                 "1001234567",
                 "Estoy bien, estoy en el albergue norte"
               )

      assert {:ok, m2} = FamiliaServer.enviar_mensaje("luis", "1001234567", "Te buscamos")
      {:ok, _} = FamiliaServer.enviar_mensaje("luis", "otro", "Para otra persona")

      assert [m1.id, m2.id] == ["MSG001", "MSG002"]
      assert m1.estado == :pendiente
      assert m1.fecha =~ ~r/^\d{4}-\d{2}-\d{2} /

      assert {:ok, lista} = FamiliaServer.listar_mensajes("1001234567")
      assert Enum.map(lista, & &1.id) == ["MSG001", "MSG002"]

      assert {:ok, %{estado: :entregado}} = FamiliaServer.marcar_mensaje("MSG001", "entregado")
      assert {:error, :ya_entregado} = FamiliaServer.marcar_mensaje("msg001", :entregado)
      assert {:ok, %{estado: :pendiente}} = FamiliaServer.marcar_mensaje("MSG001", "pendiente")
      assert {:error, :ya_pendiente} = FamiliaServer.marcar_mensaje("MSG001", "pendiente")
    end

    test "se puede dejar un mensaje para una persona que aún no está registrada" do
      assert {:ok, _} = FamiliaServer.enviar_mensaje("ana", "777", "Hola")
      assert {:ok, [_]} = FamiliaServer.listar_mensajes("777")
    end

    test "valida los datos" do
      assert {:error, :contenido_invalido} = FamiliaServer.enviar_mensaje("ana", "1", "")
      assert {:error, :destinatario_invalido} = FamiliaServer.enviar_mensaje("ana", "", "Hola")
      assert {:error, :remitente_invalido} = FamiliaServer.enviar_mensaje("", "1", "Hola")

      assert {:error, :mensaje_no_encontrado} =
               FamiliaServer.marcar_mensaje("MSG999", "entregado")

      assert {:error, :estado_invalido} = FamiliaServer.marcar_mensaje("MSG001", "leido")
      assert %{mensajes_total: 0} = FamiliaServer.resumen()
    end

    test "un mensaje con | y saltos de línea se guarda y se recupera" do
      {:ok, m} = FamiliaServer.enviar_mensaje("ana", "1", "En A | B\nllamar al 123")
      :ok = reiniciar()
      assert {:ok, [^m]} = FamiliaServer.listar_mensajes("1")
    end
  end

  describe "persistencia" do
    test "guarda en personas.txt y mensajes.txt y se recupera al reiniciar" do
      {:ok, persona} = reportar()
      {:ok, _} = FamiliaServer.cambiar_estado("1001234567", :en_albergue)
      {:ok, mensaje} = FamiliaServer.enviar_mensaje("ana", "1001234567", "Hola")

      assert File.exists?(Persistencia.ruta("personas.txt"))
      assert File.exists?(Persistencia.ruta("mensajes.txt"))

      :ok = reiniciar()

      assert {:ok, recuperada} = FamiliaServer.buscar("1001234567")
      assert recuperada.id == persona.id
      assert recuperada.estado == :en_albergue
      assert [%{a: :en_albergue}] = elem(FamiliaServer.historial("1001234567"), 1)
      assert {:ok, [^mensaje]} = FamiliaServer.listar_mensajes("1001234567")
    end

    test "un cambio que no se puede guardar no altera el estado en memoria" do
      {:ok, _} = reportar()
      # Un directorio con el nombre del archivo impide escribir personas.txt.
      File.rm!(Persistencia.ruta("personas.txt"))
      File.mkdir_p!(Persistencia.ruta("personas.txt"))

      assert {:error, _} = reportar(%{documento: "2"})
      assert {:error, :persona_no_encontrada} = FamiliaServer.buscar("2")
      assert %{personas_registradas: 1} = FamiliaServer.resumen()

      File.rm_rf!(Persistencia.ruta("personas.txt"))
    end

    test "carga los datos iniciales de ejemplo" do
      DatosPrueba.limpiar_datos()
      {:ok, _} = File.cp_r("datos_iniciales", "data_test")
      :ok = reiniciar()

      assert {:ok, %{nombre: "Andrés Gómez", estado: :en_albergue}} =
               FamiliaServer.buscar("1001234567")

      assert %{personas_registradas: 5, mensajes_total: 2, mensajes_pendientes: 1} =
               FamiliaServer.resumen()

      assert {:ok, [%{contenido: contenido}]} = FamiliaServer.listar_mensajes("1003456789")
      assert contenido =~ "tía | te esperamos"
    end
  end

  describe "concurrencia" do
    test "20 registros simultáneos con documentos distintos obtienen ids únicos" do
      resultados =
        1..20
        |> Task.async_stream(fn n -> reportar(%{documento: "doc#{n}"}) end, max_concurrency: 20)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.all?(resultados, &match?({:ok, _}, &1))
      ids = Enum.map(resultados, fn {:ok, p} -> p.id end)
      assert length(Enum.uniq(ids)) == 20
      assert %{personas_registradas: 20} = FamiliaServer.resumen()
    end

    test "10 registros simultáneos del mismo documento: solo uno se acepta" do
      resultados =
        1..10
        |> Task.async_stream(fn _ -> reportar() end, max_concurrency: 10)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :persona_ya_registrada})) == 9
      assert %{personas_registradas: 1} = FamiliaServer.resumen()
    end

    test "dos cambios de estado simultáneos incompatibles: solo uno gana" do
      {:ok, _} = reportar(%{estado: "reportada"})

      resultados =
        [:reunificada, :localizada]
        |> Task.async_stream(fn estado -> FamiliaServer.cambiar_estado("1001234567", estado) end)
        |> Enum.map(fn {:ok, r} -> r end)

      # reunificada es final: si gana primero, localizada falla; si localizada gana primero,
      # reunificada todavía es válida desde localizada. Ninguna combinación deja el historial roto.
      assert {:ok, persona} = FamiliaServer.buscar("1001234567")
      assert length(persona.historial) == Enum.count(resultados, &match?({:ok, _}, &1))
    end
  end

  test "resumen/0 cuenta personas por estado y mensajes" do
    {:ok, _} = reportar(%{documento: "1", estado: "localizada"})
    {:ok, _} = reportar(%{documento: "2", estado: "en albergue"})
    {:ok, _} = reportar(%{documento: "3", estado: "localizada"})
    {:ok, _} = FamiliaServer.enviar_mensaje("ana", "1", "Hola")

    assert %{
             personas_registradas: 3,
             personas_localizada: 2,
             personas_en_albergue: 1,
             personas_reunificada: 0,
             mensajes_total: 1,
             mensajes_pendientes: 1,
             mensajes_entregados: 0
           } = FamiliaServer.resumen()
  end
end
