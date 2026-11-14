import Config

config :emergencias,
  carpeta_datos: if(config_env() == :test, do: "data_test", else: "data")
