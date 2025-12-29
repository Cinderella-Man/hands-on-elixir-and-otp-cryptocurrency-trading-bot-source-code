require Logger

alias Hedgehog.Repo
alias Hedgehog.Streamer.Settings, as: StreamerSettings
alias Hedgehog.Strategy.Naive.Settings, as: NaiveStrategySettings

binance_client = Application.compile_env(:hedgehog, :binance_client)

Logger.info("Fetching exchange info from Binance to create streaming settings")

{:ok, %{symbols: symbols}} = binance_client.get_exchange_info()

timestamp =
  NaiveDateTime.utc_now()
  |> NaiveDateTime.truncate(:second)

base_settings = %{
  symbol: "",
  status: "off",
  inserted_at: timestamp,
  updated_at: timestamp
}

Logger.info("Inserting default streamer settings for symbols")

total_count =
  symbols
  |> Enum.map(&%{base_settings | symbol: &1["symbol"]})
  |> Enum.chunk_every(1000)
  |> Enum.reduce(0, fn batch, acc ->
    {count, nil} = Repo.insert_all(StreamerSettings, batch, on_conflict: :nothing)
    Logger.info("Inserted batch of #{count} symbols")
    acc + count
  end)

Logger.info("Inserted streamer settings for #{total_count} symbols")

%{
  chunks: chunks,
  budget: budget,
  buy_down_interval: buy_down_interval,
  profit_target: profit_target,
  rebuy_interval: rebuy_interval
} = Application.compile_env(:hedgehog, [:strategy, :naive, :defaults])

base_settings = %{
  symbol: "",
  chunks: chunks,
  budget: Decimal.new(budget),
  buy_down_interval: Decimal.new(buy_down_interval),
  profit_target: Decimal.new(profit_target),
  rebuy_interval: Decimal.new(rebuy_interval),
  status: "off",
  inserted_at: timestamp,
  updated_at: timestamp
}

Logger.info("Inserting default naive strategy settings for symbols")

total_count =
  symbols
  |> Enum.map(&%{base_settings | symbol: &1["symbol"]})
  |> Enum.chunk_every(1000)
  |> Enum.reduce(0, fn batch, acc ->
    {count, nil} = Repo.insert_all(NaiveStrategySettings, batch, on_conflict: :nothing)
    Logger.info("Inserted batch of #{count} naive settings")
    acc + count
  end)

Logger.info("Inserted naive strategy settings for #{total_count} symbols")
