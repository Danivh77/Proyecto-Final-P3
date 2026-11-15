defmodule Emergencias.DatosPrueba do
  @moduledoc """
  Datos de ejemplo reutilizables en las pruebas (ExUnit).

  ARCHIVO COMPARTIDO: cada integrante escribe SOLO dentro de su bloque.

  """

  # INTEGRANTE 1: Núcleo y usuarios

  @carpeta_pruebas "data_test"

  @doc "Usuario de ejemplo. Se le puede cambiar el tipo: ciudadano, voluntario, coordinador o administrador."
  def usuario_ejemplo(tipo \\ "coordinador") do
    %{
      username: "laura",
      password: "1234",
      nombre: "Laura Gómez",
      tipo: tipo,
      zona: "centro"
    }
  end

  @doc "Deja vacía la carpeta de datos de prueba, sin borrar la carpeta."
  def limpiar_datos do
    File.mkdir_p(@carpeta_pruebas)

    case File.ls(@carpeta_pruebas) do
      {:ok, nombres} -> Enum.each(nombres, &File.rm_rf(Path.join(@carpeta_pruebas, &1)))
      {:error, _} -> :ok
    end

    :ok
  end

  # INTEGRANTE 2: Zonas, necesidades y recursos

  alias Emergencias.Dominio.{Recurso, Zona}

  @doc "Árbol de prueba con una zona, dos sectores y un punto de atención."
  def zona_ejemplo do
    {:ok, zona} = Zona.nuevo("centro", "Centro", "zona", "crítico", 100)
    {:ok, sector_norte} = Zona.nuevo("norte", "Norte", "sector", "alto", 30)
    {:ok, sector_sur} = Zona.nuevo("sur", "Sur", "sector", "medio", 20)
    {:ok, punto} = Zona.nuevo("p01", "Puesto | Sur\nEntrada principal", "punto", "bajo", 5)

    {:ok, arbol} = Zona.agregar_hijo(zona, "centro", sector_norte)
    {:ok, arbol} = Zona.agregar_hijo(arbol, "centro", sector_sur)
    {:ok, arbol} = Zona.agregar_hijo(arbol, "sur", punto)
    arbol
  end

  @doc "Recurso de prueba con una cantidad inicial configurable."
  def recurso_ejemplo(cantidad \\ 50) do
    {:ok, recurso} = Recurso.nuevo("R001", "agua", "agua", cantidad, "litros", "centro_acopio_1")
    recurso
  end

  # Función pendiente: necesidad_ejemplo/1

  # INTEGRANTE 3: Albergues, familiares y mascotas
  # Funciones acordadas: albergue_ejemplo/1, persona_ejemplo/1,
  #                      mascota_perdida/0, mascota_encontrada/0
  #
  # Ejemplo (quitar los # y ajustar):
  #
  # def albergue_ejemplo(capacidad \\ 150) do
  #   %{codigo: "A01", nombre: "Albergue Norte", zona: "zona_norte", capacidad: capacidad}
  # end

end
