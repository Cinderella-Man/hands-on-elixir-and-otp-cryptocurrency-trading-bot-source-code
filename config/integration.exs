import Config

config :hedgehog, Hedgehog.Repo,
  database: Path.expand("../hedgehog_integration.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :hedgehog, Hedgehog.Litestream, enabled: false
