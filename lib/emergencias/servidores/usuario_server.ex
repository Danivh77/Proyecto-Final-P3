defmodule Emergencias.Servidores.UsuarioServer do
  @moduledoc """
  Guarda los usuarios registrados y los que están conectados.
  Estado: `%{usuarios: %{username => Usuario}, conectados: MapSet}`.
  """

  use GenServer

  alias Emergencias.Dominio.Usuario
  alias Emergencias.Persistencia

  @archivo "usuarios.txt"

  # API

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Conecta al usuario. Si no existe lo registra; si existe valida la contraseña.
  Devuelve `{:ok, usuario, :registrado | :autenticado}` o `{:error, motivo}`.
  """
  def connect(username, password, tipo, zona, nombre \\ "") do
    GenServer.call(__MODULE__, {:connect, username, password, tipo, zona, nombre})
  end

  @doc "Desconecta al usuario."
  def disconnect(username), do: GenServer.call(__MODULE__, {:disconnect, username})

  @doc "Indica si el usuario está conectado."
  def conectado?(username), do: GenServer.call(__MODULE__, {:conectado?, username})

  @doc "Busca un usuario por su username."
  def obtener(username), do: GenServer.call(__MODULE__, {:obtener, username})

  @doc "Lista de usuarios conectados."
  def listar_conectados, do: GenServer.call(__MODULE__, :listar_conectados)

  @doc "Totales para el comando summary."
  def resumen, do: GenServer.call(__MODULE__, :resumen)

  # Callbacks

  @impl true
  def init(:ok) do
    {:ok, lista} = Persistencia.cargar(@archivo, &Usuario.desde_linea/1)
    usuarios = Map.new(lista, fn u -> {u.username, u} end)
    {:ok, %{usuarios: usuarios, conectados: MapSet.new()}}
  end

  @impl true
  def handle_call({:connect, username, password, tipo, zona, nombre}, _from, estado) do
    cond do
      MapSet.member?(estado.conectados, username) ->
        {:reply, {:error, :ya_conectado}, estado}

      Map.has_key?(estado.usuarios, username) ->
        autenticar(estado.usuarios[username], password, estado)

      true ->
        registrar(username, password, tipo, zona, nombre, estado)
    end
  end

  def handle_call({:disconnect, username}, _from, estado) do
    if MapSet.member?(estado.conectados, username) do
      {:reply, :ok, %{estado | conectados: MapSet.delete(estado.conectados, username)}}
    else
      {:reply, {:error, :no_conectado}, estado}
    end
  end

  def handle_call({:conectado?, username}, _from, estado) do
    {:reply, MapSet.member?(estado.conectados, username), estado}
  end

  def handle_call({:obtener, username}, _from, estado) do
    case Map.fetch(estado.usuarios, username) do
      {:ok, usuario} -> {:reply, {:ok, usuario}, estado}
      :error -> {:reply, {:error, :no_encontrado}, estado}
    end
  end

  def handle_call(:listar_conectados, _from, estado) do
    {:reply, estado.conectados |> MapSet.to_list() |> Enum.sort(), estado}
  end

  def handle_call(:resumen, _from, estado) do
    resumen = %{
      usuarios_registrados: map_size(estado.usuarios),
      usuarios_conectados: MapSet.size(estado.conectados)
    }

    {:reply, resumen, estado}
  end

  defp autenticar(usuario, password, estado) do
    case Usuario.validar_password(usuario, password) do
      :ok -> {:reply, {:ok, usuario, :autenticado}, conectar(estado, usuario)}
      error -> {:reply, error, estado}
    end
  end

  defp registrar(username, password, tipo, zona, nombre, estado) do
    with {:ok, usuario} <- Usuario.nuevo(username, password, nombre, tipo, zona),
         usuarios = Map.put(estado.usuarios, username, usuario),
         :ok <- Persistencia.guardar(@archivo, Map.values(usuarios), &Usuario.a_linea/1) do
      {:reply, {:ok, usuario, :registrado}, conectar(%{estado | usuarios: usuarios}, usuario)}
    else
      error -> {:reply, error, estado}
    end
  end

  defp conectar(estado, usuario) do
    %{estado | conectados: MapSet.put(estado.conectados, usuario.username)}
  end
end
