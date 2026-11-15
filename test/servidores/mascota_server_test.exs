defmodule Emergencias.Servidores.MascotaServerTest do
  # No es async: usa el MascotaServer único del sistema y la carpeta data_test.
  use ExUnit.Case, async: false

  alias Emergencias.DatosPrueba
  alias Emergencias.Persistencia
  alias Emergencias.Servidores.MascotaServer

  setup do
    DatosPrueba.limpiar_datos()
    reiniciar()
    :ok
  end

  defp reiniciar do
    :ok = Supervisor.terminate_child(Emergencias.Supervisor, MascotaServer)
    {:ok, _} = Supervisor.restart_child(Emergencias.Supervisor, MascotaServer)
    :ok
  end

  defp perdida(extra \\ %{}) do
    {:ok, r} = MascotaServer.reportar(:perdida, Map.merge(DatosPrueba.mascota_perdida(), extra))
    r
  end

  defp encontrada(extra \\ %{}) do
    {:ok, r} =
      MascotaServer.reportar(:encontrada, Map.merge(DatosPrueba.mascota_encontrada(), extra))

    r
  end

  describe "reportar/2" do
    test "registra reportes con ids M001, M002..." do
      assert %{id: "M001", tipo: :perdida, estado: :activa} = perdida()
      assert %{id: "M002", tipo: :encontrada, estado: :activa} = encontrada()
    end

    test "acepta lost/found y datos como keyword" do
      assert {:ok, %{tipo: :perdida}} =
               MascotaServer.reportar("lost", Map.to_list(DatosPrueba.mascota_perdida()))

      assert {:ok, %{tipo: :encontrada}} =
               MascotaServer.reportar("found", DatosPrueba.mascota_encontrada())
    end

    test "valida los datos y no guarda nada si son inválidos" do
      assert {:error, :tipo_invalido} =
               MascotaServer.reportar("otro", DatosPrueba.mascota_perdida())

      sin_especie = Map.delete(DatosPrueba.mascota_perdida(), :especie)
      assert {:error, :datos_invalidos} = MascotaServer.reportar(:perdida, sin_especie)
      assert {:error, :datos_invalidos} = MascotaServer.reportar(:perdida, "texto")
      assert {:error, :datos_invalidos} = MascotaServer.reportar(:perdida, 5)
      assert %{mascotas_reportadas: 0} = MascotaServer.resumen()
    end

    test "el nombre es opcional" do
      datos = DatosPrueba.mascota_encontrada() |> Map.delete(:nombre)
      assert {:ok, %{nombre: "desconocido"}} = MascotaServer.reportar(:encontrada, datos)
    end
  end

  describe "listar/1" do
    test "filtra por especie, zona, estado y tipo" do
      perdida()
      encontrada()
      perdida(%{especie: "gato", zona: "centro"})

      assert {:ok, todos} = MascotaServer.listar()
      assert Enum.map(todos, & &1.id) == ["M001", "M002", "M003"]

      assert {:ok, perros} = MascotaServer.listar(especie: "Perro")
      assert Enum.map(perros, & &1.id) == ["M001", "M002"]

      assert {:ok, [%{id: "M003"}]} = MascotaServer.listar(zona: "centro")
      assert {:ok, [%{id: "M002"}]} = MascotaServer.listar(tipo: "found")
      assert {:ok, []} = MascotaServer.listar(estado: "resuelta")
      assert {:ok, [_, _, _]} = MascotaServer.listar(estado: "activa")
      assert {:error, :filtros_invalidos} = MascotaServer.listar("zona=centro")
    end
  end

  describe "buscar_coincidencias/0" do
    test "encuentra la pareja del flujo de ejemplo y marca ambos reportes" do
      perdida()
      encontrada()

      assert {:ok, [par]} = MascotaServer.buscar_coincidencias()
      assert %{perdida: "M001", encontrada: "M002", especie: "perro"} = par
      # zona 30 + color 25 + tamaño 20 + "collar" y "rojo" en común 10
      assert par.puntaje == 85

      assert {:ok, [uno, dos]} = MascotaServer.listar(estado: "posible coincidencia")
      assert %{coincidencia_con: "M002"} = uno
      assert %{coincidencia_con: "M001"} = dos
    end

    test "no marca nada si no hay pareja que llegue al umbral" do
      perdida()
      encontrada(%{especie: "gato"})
      encontrada(%{color: "blanca", tamano: "grande", zona: "centro", caracteristicas: ""})

      assert {:ok, []} = MascotaServer.buscar_coincidencias()
      assert {:ok, []} = MascotaServer.listar(estado: "posible_coincidencia")
    end

    test "repetir la búsqueda da el mismo resultado" do
      perdida()
      encontrada()
      assert {:ok, primero} = MascotaServer.buscar_coincidencias()
      assert {:ok, ^primero} = MascotaServer.buscar_coincidencias()
      assert %{mascotas_posibles_coincidencias: 2} = MascotaServer.resumen()
    end

    test "una encontrada no se reparte a dos perdidas: gana la de mayor puntaje" do
      l1 = perdida(%{caracteristicas: "collar rojo orejas caidas"})
      l2 = perdida(%{tamano: "grande", caracteristicas: "collar rojo"})
      f = encontrada()

      assert {:ok, [par]} = MascotaServer.buscar_coincidencias()
      assert par.encontrada == f.id
      assert par.perdida == l1.id
      assert par.perdida != l2.id
      assert {:ok, [_, _]} = MascotaServer.listar(estado: "posible_coincidencia")
    end

    test "ignora los reportes ya resueltos" do
      l = perdida()
      f = encontrada()
      {:ok, _} = MascotaServer.confirmar_coincidencia(l.id, f.id)
      nueva = encontrada()

      assert {:ok, []} = MascotaServer.buscar_coincidencias()

      # La nueva encontrada no coincide con la perdida ya cerrada y sigue activa.
      assert {:ok, [%{id: id}]} = MascotaServer.listar(estado: "activa")
      assert id == nueva.id
    end

    test "sin reportes devuelve lista vacía" do
      assert {:ok, []} = MascotaServer.buscar_coincidencias()
    end
  end

  describe "confirmar_coincidencia/2" do
    test "cierra ambos reportes" do
      l = perdida()
      f = encontrada()

      assert {:ok, [a, b]} = MascotaServer.confirmar_coincidencia(l.id, f.id)
      assert %{estado: :resuelta, coincidencia_con: "M002"} = a
      assert %{estado: :resuelta, coincidencia_con: "M001"} = b
      assert %{mascotas_resueltas: 2, mascotas_perdidas_abiertas: 0} = MascotaServer.resumen()
    end

    test "acepta los ids en cualquier orden y en minúsculas" do
      perdida()
      encontrada()

      assert {:ok, [%{id: "M002"}, %{id: "M001"}]} =
               MascotaServer.confirmar_coincidencia("m002", " M001 ")
    end

    test "no se puede confirmar dos veces el mismo reporte" do
      l = perdida()
      f = encontrada()
      otra = encontrada(%{contacto: "3009990000"})

      assert {:ok, _} = MascotaServer.confirmar_coincidencia(l.id, f.id)
      assert {:error, :ya_resuelto} = MascotaServer.confirmar_coincidencia(l.id, f.id)
      assert {:error, :ya_resuelto} = MascotaServer.confirmar_coincidencia(l.id, otra.id)
      assert {:error, :ya_resuelto} = MascotaServer.confirmar_coincidencia(f.id, l.id)
      # La encontrada libre no se tocó.
      assert {:ok, [%{id: id, estado: :activa}]} = MascotaServer.listar(estado: "activa")
      assert id == otra.id
    end

    test "rechaza parejas inválidas sin cambiar nada" do
      l = perdida()
      l2 = perdida()
      gato = encontrada(%{especie: "gato"})

      assert {:error, :reporte_no_encontrado} = MascotaServer.confirmar_coincidencia(l.id, "M999")
      assert {:error, :reporte_no_encontrado} = MascotaServer.confirmar_coincidencia(nil, l.id)
      assert {:error, :mismo_reporte} = MascotaServer.confirmar_coincidencia(l.id, l.id)
      assert {:error, :tipos_incompatibles} = MascotaServer.confirmar_coincidencia(l.id, l2.id)
      assert {:error, :especies_distintas} = MascotaServer.confirmar_coincidencia(l.id, gato.id)
      assert %{mascotas_resueltas: 0} = MascotaServer.resumen()
    end
  end

  describe "persistencia" do
    test "guarda en mascotas.txt y se recupera al reiniciar" do
      l = perdida()
      f = encontrada()
      {:ok, _} = MascotaServer.buscar_coincidencias()

      assert File.exists?(Persistencia.ruta("mascotas.txt"))
      :ok = reiniciar()

      assert {:ok, [uno, dos]} = MascotaServer.listar()
      assert %{id: "M001", estado: :posible_coincidencia, coincidencia_con: "M002"} = uno
      assert %{id: "M002", estado: :posible_coincidencia, coincidencia_con: "M001"} = dos
      assert uno.nombre == l.nombre and dos.nombre == f.nombre

      {:ok, _} = MascotaServer.confirmar_coincidencia("M001", "M002")
      :ok = reiniciar()
      assert %{mascotas_resueltas: 2} = MascotaServer.resumen()
    end

    test "el siguiente id continúa después de reiniciar" do
      perdida()
      :ok = reiniciar()
      assert %{id: "M002"} = encontrada()
    end

    test "carga los datos iniciales de ejemplo" do
      DatosPrueba.limpiar_datos()
      {:ok, _} = File.cp_r("datos_iniciales", "data_test")
      :ok = reiniciar()

      assert %{
               mascotas_reportadas: 3,
               mascotas_perdidas_abiertas: 2,
               mascotas_encontradas_abiertas: 1
             } = MascotaServer.resumen()

      assert {:ok, [%{nombre: "Luna", caracteristicas: "collar rojo y orejas caídas"}]} =
               MascotaServer.listar(especie: "perro")
    end
  end

  describe "concurrencia" do
    test "dos confirmaciones simultáneas del mismo reporte: solo una se acepta" do
      l = perdida()
      f1 = encontrada()
      f2 = encontrada(%{contacto: "3009990000"})

      resultados =
        [f1.id, f2.id]
        |> Task.async_stream(fn id -> MascotaServer.confirmar_coincidencia(l.id, id) end)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :ya_resuelto})) == 1
      assert %{mascotas_resueltas: 2} = MascotaServer.resumen()
    end

    test "10 confirmaciones simultáneas de la misma pareja: solo una se acepta" do
      l = perdida()
      f = encontrada()

      resultados =
        1..10
        |> Task.async_stream(fn _ -> MascotaServer.confirmar_coincidencia(l.id, f.id) end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :ya_resuelto})) == 9
    end

    test "20 reportes simultáneos reciben ids distintos" do
      resultados =
        1..20
        |> Task.async_stream(
          fn n ->
            MascotaServer.reportar(
              :perdida,
              Map.put(DatosPrueba.mascota_perdida(), :contacto, "300#{n}")
            )
          end,
          max_concurrency: 20
        )
        |> Enum.map(fn {:ok, {:ok, r}} -> r.id end)

      assert length(Enum.uniq(resultados)) == 20
      assert %{mascotas_reportadas: 20} = MascotaServer.resumen()
    end
  end

  test "resumen/0 cuenta los reportes por situación" do
    perdida()
    encontrada()
    perdida(%{especie: "gato", zona: "centro"})
    {:ok, _} = MascotaServer.buscar_coincidencias()

    assert %{
             mascotas_reportadas: 3,
             mascotas_perdidas_abiertas: 2,
             mascotas_encontradas_abiertas: 1,
             mascotas_posibles_coincidencias: 2,
             mascotas_resueltas: 0
           } = MascotaServer.resumen()
  end
end
