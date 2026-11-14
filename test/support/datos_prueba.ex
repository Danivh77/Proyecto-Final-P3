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
      username: "Valen",
      password: "1234",
      nombre: "Valentina Gómez",
      tipo: tipo,
      zona: "centro"
    }
  end

  @doc "Borra y vuelve a crear la carpeta de datos de prueba, para empezar cada prueba limpia."
  def limpiar_datos do
    File.rm_rf!(@carpeta_pruebas)
    File.mkdir_p!(@carpeta_pruebas)
    :ok
  end

  # INTEGRANTE 2: Zonas, necesidades y recursos
  # Funciones acordadas: zona_ejemplo/0 (árbol de 3 niveles),
  #                      recurso_ejemplo/1, necesidad_ejemplo/1
  #
  # Ejemplo (quitar los # y ajustar):
  #
  # def recurso_ejemplo(cantidad \\ 50) do
  #   %{codigo: "R001", nombre: "agua", categoria: "agua", cantidad: cantidad,
  #     unidad: "litros", ubicacion: "centro_acopio_1"}
  # end

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
