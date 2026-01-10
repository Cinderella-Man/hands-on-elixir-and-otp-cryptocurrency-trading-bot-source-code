import Config

config :hedgehog, Hedgehog.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "hedgehog_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
