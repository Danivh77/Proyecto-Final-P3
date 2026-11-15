defmodule Emergencias.Dominio.MensajeTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Persistencia

  defp mensaje(contenido \\ "Estoy bien, estoy en el albergue norte") do
    {:ok, m} =
      Mensaje.nuevo("laura", "1001", contenido, id: "MSG001", fecha: "2026-11-15 10:00:00")

    m
  end

  describe "nuevo/4" do
    test "crea un mensaje pendiente" do
      assert {:ok, m} = Mensaje.nuevo("laura", "1001", "Hola")
      assert m.estado == :pendiente
      assert m.id == nil
      assert m.fecha == nil
    end

    test "recibe id y fecha por opciones" do
      m = mensaje()
      assert m.id == "MSG001"
      assert m.fecha == "2026-11-15 10:00:00"
    end

    test "valida los campos" do
      assert {:error, :remitente_invalido} = Mensaje.nuevo("", "1001", "Hola")
      assert {:error, :destinatario_invalido} = Mensaje.nuevo("laura", " ", "Hola")
      assert {:error, :contenido_invalido} = Mensaje.nuevo("laura", "1001", "")
      assert {:error, :contenido_invalido} = Mensaje.nuevo("laura", "1001", nil)

      assert {:error, :contenido_invalido} =
               Mensaje.nuevo("laura", "1001", String.duplicate("a", 501))
    end
  end

  describe "marcar_entregado/1 y marcar_pendiente/1" do
    test "cambian el estado y avisan si ya estaba así" do
      m = mensaje()
      assert {:error, :ya_pendiente} = Mensaje.marcar_pendiente(m)
      assert {:ok, entregado} = Mensaje.marcar_entregado(m)
      assert entregado.estado == :entregado
      assert {:error, :ya_entregado} = Mensaje.marcar_entregado(entregado)
      assert {:ok, %{estado: :pendiente}} = Mensaje.marcar_pendiente(entregado)
    end
  end

  describe "a_linea/1 y desde_linea/1" do
    test "guardar y volver a leer da el mismo mensaje" do
      m = mensaje()
      assert {:ok, ^m} = m |> Mensaje.a_linea() |> Mensaje.desde_linea()
    end

    test "el carácter | del contenido se escapa y se recupera" do
      m = mensaje("Estoy en A | B, no en C\\D")
      linea = Mensaje.a_linea(m)
      assert length(Persistencia.separar_campos(linea)) == 6
      assert {:ok, ^m} = Mensaje.desde_linea(linea)
    end

    test "textos con caracteres especiales sobreviven a guardar y leer" do
      for texto <- ["a|b", "a\\b", "a\\|b", "\\p", "||", "ñandú | ç", "\\\\n", "x\\"] do
        m = mensaje(texto)
        assert {:ok, ^m} = m |> Mensaje.a_linea() |> Mensaje.desde_linea()
      end
    end

    test "ignora los retornos de carro (\\r) del contenido" do
      assert {:ok, m} = Mensaje.nuevo("laura", "1001", "hola\r\nmundo")
      assert m.contenido == "hola\nmundo"
    end

    test "Persistencia.parsear_lineas/2 lo recupera junto con una línea dañada" do
      m = mensaje("con | pipe y\nsalto")
      lineas = [Mensaje.a_linea(m), "linea dañada", ""]
      assert [^m] = Persistencia.parsear_lineas(lineas, &Mensaje.desde_linea/1)
    end

    test "conserva el estado entregado y los saltos de línea" do
      {:ok, m} = Mensaje.marcar_entregado(mensaje("primera\nsegunda"))
      assert {:ok, ^m} = m |> Mensaje.a_linea() |> Mensaje.desde_linea()
    end

    test "las líneas dañadas devuelven error" do
      assert {:error, :linea_invalida} = Mensaje.desde_linea("")
      assert {:error, :linea_invalida} = Mensaje.desde_linea("MSG1|f|a|b|c")
      assert {:error, :linea_invalida} = Mensaje.desde_linea("MSG1|f|a|b|c|raro")
      assert {:error, :linea_invalida} = Mensaje.desde_linea("MSG1|f||b|c|pendiente")
      assert {:error, :linea_invalida} = Mensaje.desde_linea(nil)
    end
  end
end
