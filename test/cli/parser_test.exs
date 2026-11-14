defmodule Emergencias.CLI.ParserTest do
  use ExUnit.Case, async: true

  alias Emergencias.CLI.Parser

  test "separa el comando y sus argumentos" do
    assert Parser.parsear("assign_resource N001 agua 30") ==
             {:ok, {:assign_resource, ["N001", "agua", "30"]}}
  end

  test "el texto entre comillas queda como un solo argumento" do
    assert Parser.parsear(~s(send_family_message 1094 "Estoy bien, en el albergue")) ==
             {:ok, {:send_family_message, ["1094", "Estoy bien, en el albergue"]}}
  end

  test "ignora espacios de más y no distingue mayúsculas en el comando" do
    assert Parser.parsear("   LIST_NEEDS    zona=centro  ") ==
             {:ok, {:list_needs, ["zona=centro"]}}
  end

  test "errores de entrada" do
    assert Parser.parsear("   ") == {:error, :comando_vacio}
    assert Parser.parsear("volar alto") == {:error, {:comando_desconocido, "volar"}}
    assert Parser.parsear(~s(report_person 1094 "Andrés)) == {:error, :comillas_sin_cerrar}
  end

  test "filtros" do
    assert Parser.parsear_filtros(["zona=centro", "prioridad=critica"]) ==
             {:ok, [zona: "centro", prioridad: "critica"]}

    assert Parser.parsear_filtros(["color=rojo"]) == {:error, {:filtro_invalido, "color=rojo"}}
    assert Parser.parsear_filtros(["zona="]) == {:error, {:filtro_invalido, "zona="}}
  end

  test "conversión de números" do
    assert Parser.a_entero("30") == {:ok, 30}
    assert Parser.a_entero("treinta") == {:error, {:numero_invalido, "treinta"}}
    assert Parser.a_entero_positivo("0") == {:error, {:cantidad_invalida, "0"}}
    assert Parser.a_entero_positivo("-5") == {:error, {:cantidad_invalida, "-5"}}
  end
end
