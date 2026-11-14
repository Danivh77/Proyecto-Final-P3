defmodule Emergencias.Dominio.Usuario do
  @moduledoc """
  Usuario del sistema. La contraseña se guarda cifrada con SHA-256, nunca en texto plano.
  """

  alias Emergencias.Persistencia

  @tipos ~w(ciudadano voluntario coordinador administrador)

  defstruct [:username, :password_hash, :nombre, :tipo, :zona]

  @doc "Guard para usar en `when`: el tipo de usuario es válido."
  defguard tipo_valido(tipo) when tipo in @tipos

  @doc "Tipos de usuario permitidos."
  def tipos, do: @tipos

  @doc "Indica si el tipo de usuario es válido."
  def tipo_valido?(tipo), do: tipo_valido(tipo)

  @doc """
  Crea un usuario validando sus datos. Si no se da nombre completo, se usa el username.
  Devuelve `{:ok, usuario}` o `{:error, motivo}`.
  """
  def nuevo(username, password, nombre, tipo, zona) do
    nombre = if vacio?(nombre), do: username, else: nombre

    cond do
      not username_valido?(username) ->
        {:error, :usuario_invalido}

      not password_valida?(password) ->
        {:error, :contrasena_invalida}

      not tipo_valido?(tipo) ->
        {:error, :tipo_invalido}

      vacio?(zona) ->
        {:error, :zona_invalida}

      true ->
        {:ok,
         %__MODULE__{
           username: username,
           password_hash: hash_password(password),
           nombre: nombre,
           tipo: tipo,
           zona: zona
         }}
    end
  end

  @doc "Cifra una contraseña con SHA-256."
  def hash_password(password) when is_binary(password) do
    :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)
  end

  @doc "Comprueba la contraseña. Devuelve `:ok` o `{:error, :contrasena_incorrecta}`."
  def validar_password(%__MODULE__{password_hash: hash}, password) when is_binary(password) do
    if hash_password(password) == hash, do: :ok, else: {:error, :contrasena_incorrecta}
  end

  @doc "Convierte el usuario en una línea de texto."
  def a_linea(%__MODULE__{} = u) do
    Persistencia.unir_campos([u.username, u.password_hash, u.nombre, u.tipo, u.zona])
  end

  @doc "Convierte una línea de texto en usuario."
  def desde_linea(linea) do
    case Persistencia.separar_campos(linea) do
      [username, hash, nombre, tipo, zona] when tipo_valido(tipo) ->
        {:ok,
         %__MODULE__{
           username: username,
           password_hash: hash,
           nombre: nombre,
           tipo: tipo,
           zona: zona
         }}

      _ ->
        {:error, :linea_invalida}
    end
  end

  defp username_valido?(username) when is_binary(username),
    do: String.match?(username, ~r/^[A-Za-z0-9_]{3,20}$/)

  defp username_valido?(_), do: false

  defp password_valida?(password) when is_binary(password), do: String.length(password) >= 4
  defp password_valida?(_), do: false

  defp vacio?(texto) when is_binary(texto), do: String.trim(texto) == ""
  defp vacio?(_), do: true
end
