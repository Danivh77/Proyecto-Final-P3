defmodule Emergencias.Servidores.AlbergueServerTest do
  # No es async: usa los servidores únicos del sistema y la carpeta data_test.
  use ExUnit.Case, async: false

  alias Emergencias.DatosPrueba
  alias Emergencias.Dominio.Albergue
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.{AlbergueServer, AlbergueSupervisor, FamiliaServer}

  setup do
    DatosPrueba.limpiar_datos()
    reiniciar(FamiliaServer)
    reiniciar(AlbergueSupervisor)
    :ok
  end

  # Reinicia un hijo del árbol para que vuelva a cargar los archivos de data_test.
  defp reiniciar(modulo) do
    :ok = Supervisor.terminate_child(Emergencias.Supervisor, modulo)
    {:ok, _} = Supervisor.restart_child(Emergencias.Supervisor, modulo)
    :ok
  end

  defp crear(capacidad \\ 150, extra \\ %{}) do
    d = Map.merge(DatosPrueba.albergue_ejemplo(capacidad), extra)
    AlbergueSupervisor.crear_albergue(d.codigo, d.nombre, d.zona, d.capacidad)
  end

  defp archivo_guardado(codigo) do
    {:ok, [albergue]} = Persistencia.cargar("albergues/#{codigo}.txt", &Albergue.desde_linea/1)

    albergue
  end

  describe "crear_albergue/4" do
    test "crea el albergue, su proceso y su archivo" do
      assert {:ok, %Albergue{codigo: "A01", capacidad: 150}} = crear()
      assert [{pid, _}] = Registry.lookup(Emergencias.Registry, {:albergue, "A01"})
      assert Process.alive?(pid)
      assert File.exists?(Persistencia.ruta("albergues/A01.txt"))
      assert %Albergue{nombre: "Albergue Norte"} = archivo_guardado("A01")
    end

    test "cada albergue guarda su propio archivo" do
      {:ok, _} = crear()
      {:ok, _} = crear(80, %{codigo: "A02", nombre: "Albergue Centro", zona: "centro"})

      assert Persistencia.listar_archivos("albergues") == [
               "albergues/A01.txt",
               "albergues/A02.txt"
             ]
    end

    test "rechaza un código repetido, también con otras mayúsculas" do
      assert {:ok, _} = crear()
      assert {:error, :albergue_ya_existe} = crear()
      assert {:error, :albergue_ya_existe} = crear(10, %{codigo: "a01"})
      assert {:error, :albergue_ya_existe} = crear(10, %{codigo: " A01 "})
      assert {:ok, [%{capacidad: 150}]} = AlbergueSupervisor.listar()
    end

    test "valida los datos" do
      assert {:error, :capacidad_invalida} = crear(-5)
      assert {:error, :capacidad_invalida} = crear(0)
      assert {:error, :codigo_invalido} = crear(10, %{codigo: "../A01"})
      assert {:error, :codigo_invalido} = crear(10, %{codigo: ""})
      assert {:error, :datos_invalidos} = crear(10, %{nombre: ""})
      assert {:ok, []} = AlbergueSupervisor.listar()
    end

    test "10 creaciones simultáneas del mismo código: solo una se acepta" do
      resultados =
        1..10
        |> Task.async_stream(fn _ -> crear() end, max_concurrency: 10)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :albergue_ya_existe})) == 9
      assert %{albergues_registrados: 1} = AlbergueSupervisor.resumen()
    end
  end

  describe "registrar_entrada/2 y registrar_salida/2" do
    test "registra ingresos y salidas y calcula cupos" do
      {:ok, _} = crear(3)

      assert {:ok, %{ocupantes: ocupantes}} = AlbergueServer.registrar_entrada("A01", "100")
      assert MapSet.to_list(ocupantes) == ["100"]
      assert {:ok, %{cupos: 2, ocupacion: 1}} = AlbergueServer.consultar("A01")

      assert {:error, :ya_esta_dentro} = AlbergueServer.registrar_entrada("A01", "100")
      assert {:ok, _} = AlbergueServer.registrar_salida("A01", "100")
      assert {:error, :no_esta_dentro} = AlbergueServer.registrar_salida("A01", "100")
      assert {:ok, %{cupos: 3, ocupacion: 0}} = AlbergueServer.consultar("A01")
    end

    test "acepta el código en minúsculas" do
      {:ok, _} = crear()
      assert {:ok, _} = AlbergueServer.registrar_entrada("a01", "100")
      assert {:ok, %{ocupacion: 1}} = AlbergueServer.consultar(" a01 ")
    end

    test "no supera la capacidad máxima" do
      {:ok, _} = crear(2)
      assert {:ok, _} = AlbergueServer.registrar_entrada("A01", "1")
      assert {:ok, _} = AlbergueServer.registrar_entrada("A01", "2")
      assert {:error, :capacidad_llena} = AlbergueServer.registrar_entrada("A01", "3")
      assert {:ok, %{ocupacion: 2, cupos: 0, porcentaje: 100.0}} = AlbergueServer.consultar("A01")
    end

    test "valida el documento y el albergue" do
      {:ok, _} = crear()
      assert {:error, :documento_invalido} = AlbergueServer.registrar_entrada("A01", "")
      assert {:error, :documento_invalido} = AlbergueServer.registrar_entrada("A01", nil)
      assert {:error, :albergue_no_encontrado} = AlbergueServer.registrar_entrada("Z99", "1")
      assert {:error, :albergue_no_encontrado} = AlbergueServer.registrar_salida("Z99", "1")
      assert {:error, :albergue_no_encontrado} = AlbergueServer.consultar("Z99")
      assert {:error, :albergue_no_encontrado} = AlbergueServer.consultar(nil)
    end

    test "una persona sin registrar en FamiliaServer puede ingresar igual" do
      {:ok, _} = crear()
      assert {:ok, _} = AlbergueServer.registrar_entrada("A01", "999")
      assert {:error, :persona_no_encontrada} = FamiliaServer.buscar("999")
    end

    test "al ingresar, la persona registrada pasa a :en_albergue" do
      {:ok, _} = crear()
      d = DatosPrueba.persona_ejemplo()

      {:ok, _} =
        FamiliaServer.reportar_persona(d.documento, d.nombre, d.edad, d.zona, "localizada")

      assert {:ok, _} = AlbergueServer.registrar_entrada("A01", d.documento)

      assert {:ok, %{estado: :en_albergue, historial: [{_fecha, :localizada, :en_albergue}]}} =
               FamiliaServer.buscar(d.documento)
    end

    test "si el cambio de estado de la persona no es válido, el ingreso no se registra" do
      {:ok, _} = crear()
      d = DatosPrueba.persona_ejemplo()

      {:ok, _} =
        FamiliaServer.reportar_persona(d.documento, d.nombre, d.edad, d.zona, "reunificada")

      assert {:error, :transicion_invalida} = AlbergueServer.registrar_entrada("A01", d.documento)
      assert {:ok, %{ocupacion: 0}} = AlbergueServer.consultar("A01")
      assert %Albergue{} = albergue = archivo_guardado("A01")
      assert Albergue.ocupacion(albergue) == 0
    end

    test "una persona que ya está en otro albergue no puede ingresar a un segundo" do
      {:ok, _} = crear()
      {:ok, _} = crear(50, %{codigo: "A02", nombre: "Albergue Centro", zona: "centro"})
      d = DatosPrueba.persona_ejemplo()

      {:ok, _} =
        FamiliaServer.reportar_persona(d.documento, d.nombre, d.edad, d.zona, "localizada")

      assert {:ok, _} = AlbergueServer.registrar_entrada("A01", d.documento)
      assert {:error, :transicion_invalida} = AlbergueServer.registrar_entrada("A02", d.documento)
      assert {:ok, %{ocupacion: 0}} = AlbergueServer.consultar("A02")
    end
  end

  describe "concurrencia" do
    test "30 ingresos simultáneos en un albergue de 10 cupos nunca superan la capacidad" do
      {:ok, _} = crear(10)

      resultados =
        1..30
        |> Task.async_stream(fn n -> AlbergueServer.registrar_entrada("A01", "doc#{n}") end,
          max_concurrency: 30
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 10
      assert Enum.count(resultados, &(&1 == {:error, :capacidad_llena})) == 20
      assert {:ok, %{ocupacion: 10, cupos: 0}} = AlbergueServer.consultar("A01")
      assert Albergue.ocupacion(archivo_guardado("A01")) == 10
    end

    test "el mismo documento ingresando 10 veces a la vez entra una sola vez" do
      {:ok, _} = crear()

      resultados =
        1..10
        |> Task.async_stream(fn _ -> AlbergueServer.registrar_entrada("A01", "123") end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :ya_esta_dentro})) == 9
    end

    test "ingresos y salidas mezclados terminan con la ocupación correcta" do
      {:ok, _} = crear(100)
      for n <- 1..20, do: {:ok, _} = AlbergueServer.registrar_entrada("A01", "doc#{n}")

      1..20
      |> Task.async_stream(
        fn n ->
          if rem(n, 2) == 0,
            do: AlbergueServer.registrar_salida("A01", "doc#{n}"),
            else: AlbergueServer.registrar_entrada("A01", "nuevo#{n}")
        end,
        max_concurrency: 20
      )
      |> Enum.each(fn {:ok, r} -> assert match?({:ok, _}, r) end)

      # 10 salieron (pares) y 10 nuevos entraron (impares): 20 - 10 + 10.
      assert {:ok, %{ocupacion: 20}} = AlbergueServer.consultar("A01")
    end

    test "albergues distintos funcionan de forma independiente" do
      {:ok, _} = crear(5)
      {:ok, _} = crear(5, %{codigo: "A02", nombre: "Albergue Centro", zona: "centro"})

      1..10
      |> Task.async_stream(
        fn n ->
          AlbergueServer.registrar_entrada(if(rem(n, 2) == 0, do: "A01", else: "A02"), "doc#{n}")
        end,
        max_concurrency: 10
      )
      |> Enum.each(fn {:ok, r} -> assert match?({:ok, _}, r) end)

      assert {:ok, %{ocupacion: 5}} = AlbergueServer.consultar("A01")
      assert {:ok, %{ocupacion: 5}} = AlbergueServer.consultar("A02")
    end
  end

  describe "asociar_recurso/2 y asociar_necesidad/2" do
    test "asocia sin repetir y lo muestra en consultar/1" do
      {:ok, _} = crear()
      assert {:ok, _} = AlbergueServer.asociar_recurso("A01", "R001")
      assert {:error, :ya_asociado} = AlbergueServer.asociar_recurso("A01", "R001")
      assert {:ok, _} = AlbergueServer.asociar_necesidad("A01", "N001")
      assert {:error, :ya_asociado} = AlbergueServer.asociar_necesidad("A01", "N001")
      assert {:error, :datos_invalidos} = AlbergueServer.asociar_recurso("A01", "")
      assert {:error, :albergue_no_encontrado} = AlbergueServer.asociar_recurso("Z99", "R001")

      assert {:ok, %{recursos: ["R001"], necesidades: ["N001"]}} = AlbergueServer.consultar("A01")
    end
  end

  describe "consultar/1" do
    test "devuelve la información completa" do
      {:ok, _} = crear(4)
      {:ok, _} = AlbergueServer.registrar_entrada("A01", "200")
      {:ok, _} = AlbergueServer.registrar_entrada("A01", "100")

      assert {:ok, info} = AlbergueServer.consultar("A01")

      assert %{
               codigo: "A01",
               nombre: "Albergue Norte",
               zona: "zona_norte",
               capacidad: 4,
               ocupacion: 2,
               cupos: 2,
               porcentaje: 50.0,
               ocupantes: ["100", "200"]
             } = info
    end
  end

  describe "persistencia" do
    test "el estado se guarda en su archivo después de cada cambio" do
      {:ok, _} = crear(10)
      {:ok, _} = AlbergueServer.registrar_entrada("A01", "100")
      {:ok, _} = AlbergueServer.registrar_entrada("A01", "200")
      {:ok, _} = AlbergueServer.registrar_salida("A01", "100")
      {:ok, _} = AlbergueServer.asociar_recurso("A01", "R001")

      guardado = archivo_guardado("A01")
      assert MapSet.to_list(guardado.ocupantes) == ["200"]
      assert guardado.recursos == ["R001"]
    end

    test "al reiniciar el supervisor se levanta un proceso por cada archivo con su estado" do
      {:ok, _} = crear(10)
      {:ok, _} = crear(20, %{codigo: "A02", nombre: "Albergue Centro", zona: "centro"})
      {:ok, _} = AlbergueServer.registrar_entrada("A01", "100")
      {:ok, _} = AlbergueServer.asociar_necesidad("A02", "N001")

      reiniciar(AlbergueSupervisor)

      assert {:ok, %{ocupantes: ["100"], capacidad: 10}} = AlbergueServer.consultar("A01")
      assert {:ok, %{necesidades: ["N001"], capacidad: 20}} = AlbergueServer.consultar("A02")
      assert %{albergues_registrados: 2} = AlbergueSupervisor.resumen()
    end

    test "cargar_existentes/0 ignora archivos dañados" do
      {:ok, _} = crear()
      File.write!(Persistencia.ruta("albergues/BAD.txt"), "esto no es un albergue\n")
      reiniciar(AlbergueSupervisor)

      assert {:ok, [%{codigo: "A01"}]} = AlbergueSupervisor.listar()
    end

    test "si el proceso de un albergue falla, el supervisor lo reinicia con su último estado" do
      {:ok, _} = crear(10)
      {:ok, _} = AlbergueServer.registrar_entrada("A01", "100")

      [{pid, _}] = Registry.lookup(Emergencias.Registry, {:albergue, "A01"})
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert {:ok, %{ocupantes: ["100"]}} = esperar_albergue("A01")
    end

    test "carga los datos iniciales de ejemplo" do
      DatosPrueba.limpiar_datos()
      {:ok, _} = File.cp_r("datos_iniciales", "data_test")
      reiniciar(FamiliaServer)
      reiniciar(AlbergueSupervisor)

      assert {:ok, %{capacidad: 150, ocupacion: 2, cupos: 148}} = AlbergueServer.consultar("A01")
      assert {:ok, %{capacidad: 80, ocupacion: 0}} = AlbergueServer.consultar("A02")
    end

    test "un ingreso nuevo de una persona de los datos iniciales cambia su estado" do
      DatosPrueba.limpiar_datos()
      {:ok, _} = File.cp_r("datos_iniciales", "data_test")
      reiniciar(FamiliaServer)
      reiniciar(AlbergueSupervisor)

      # Juan Torres (1005678901) está "localizada" en los datos iniciales.
      assert {:ok, _} = AlbergueServer.registrar_entrada("A02", "1005678901")
      assert {:ok, %{estado: :en_albergue}} = FamiliaServer.buscar("1005678901")
    end
  end

  describe "AlbergueSupervisor" do
    setup do
      {:ok, _} = crear(100, %{codigo: "A01"})
      {:ok, _} = crear(10, %{codigo: "A02", nombre: "Albergue Centro", zona: "centro"})
      {:ok, _} = crear(20, %{codigo: "A03", nombre: "Albergue Sur", zona: "zona_sur"})
      for n <- 1..5, do: {:ok, _} = AlbergueServer.registrar_entrada("A01", "a#{n}")
      for n <- 1..8, do: {:ok, _} = AlbergueServer.registrar_entrada("A02", "b#{n}")
      for n <- 1..10, do: {:ok, _} = AlbergueServer.registrar_entrada("A03", "c#{n}")
      :ok
    end

    test "listar/0 devuelve todos ordenados por código" do
      assert {:ok, lista} = AlbergueSupervisor.listar()
      assert Enum.map(lista, & &1.codigo) == ["A01", "A02", "A03"]

      assert [%{ocupacion: 5, cupos: 95}, %{ocupacion: 8, cupos: 2}, %{ocupacion: 10, cupos: 10}] =
               lista
    end

    test "cupos_disponibles/0" do
      assert {:ok, lista} = AlbergueSupervisor.cupos_disponibles()

      assert [
               %{codigo: "A01", cupos: 95},
               %{codigo: "A02", cupos: 2},
               %{codigo: "A03", cupos: 10}
             ] = lista
    end

    test "mas_ocupados/1 ordena por porcentaje y respeta el límite" do
      assert {:ok, lista} = AlbergueSupervisor.mas_ocupados()
      assert Enum.map(lista, & &1.codigo) == ["A02", "A03", "A01"]
      assert [%{porcentaje: 80.0}, %{porcentaje: 50.0}, %{porcentaje: 5.0}] = lista

      assert {:ok, [%{codigo: "A02"}, %{codigo: "A03"}]} = AlbergueSupervisor.mas_ocupados(2)
      assert {:ok, [%{codigo: "A02"}]} = AlbergueSupervisor.mas_ocupados(1)
      assert {:error, :limite_invalido} = AlbergueSupervisor.mas_ocupados(0)
      assert {:error, :limite_invalido} = AlbergueSupervisor.mas_ocupados("2")
    end

    test "mas_ocupados/1 desempata por número de ocupantes y luego por código" do
      {:ok, _} = crear(40, %{codigo: "A04", nombre: "Otro", zona: "centro"})
      for n <- 1..20, do: {:ok, _} = AlbergueServer.registrar_entrada("A04", "d#{n}")

      # A03 y A04 tienen 50%, pero A04 tiene más ocupantes.
      assert {:ok, [_, primero, segundo | _]} = AlbergueSupervisor.mas_ocupados()
      assert primero.codigo == "A04"
      assert segundo.codigo == "A03"
    end

    test "resumen/0 suma capacidad, ocupación y cupos" do
      assert %{
               albergues_registrados: 3,
               albergues_capacidad_total: 130,
               albergues_ocupacion_total: 23,
               albergues_cupos_libres: 107
             } = AlbergueSupervisor.resumen()
    end
  end

  test "sin albergues, las consultas devuelven vacío" do
    assert {:ok, []} = AlbergueSupervisor.listar()
    assert {:ok, []} = AlbergueSupervisor.mas_ocupados()
    assert {:ok, []} = AlbergueSupervisor.cupos_disponibles()

    assert %{albergues_registrados: 0, albergues_capacidad_total: 0} =
             AlbergueSupervisor.resumen()
  end

  # Tras un fallo el supervisor reinicia el proceso; se espera a que vuelva a registrarse.
  defp esperar_albergue(codigo, intentos \\ 50) do
    case AlbergueServer.consultar(codigo) do
      {:error, :albergue_no_encontrado} when intentos > 0 ->
        Process.sleep(20)
        esperar_albergue(codigo, intentos - 1)

      resultado ->
        resultado
    end
  end
end
