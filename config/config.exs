# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :streamer,
  ecto_repos: [Streamer.Repo]

config :streamer, Streamer.Repo,
  database: "streamer",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :naive,
  ecto_repos: [Naive.Repo],
  binance_client: BinanceMock,
  trading: %{
    defaults: %{
      chunks: 5,
      budget: 1000.0,
      buy_down_interval: 0.0001,
      profit_interval: -0.0012,
      rebuy_interval: 0.001
    }
  }

config :naive, Naive.Repo,
  database: "naive",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :binance,
  api_key: "YOUR-API-KEY-HERE",
  secret_key: "YOUR-SECRET-KEY-HERE"

config :logger,
  level: :info
