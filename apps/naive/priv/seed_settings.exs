require Logger

alias Naive.Repo
alias Naive.Schema.Settings

binance_client = Application.compile_env(:naive, :binance_client)

Logger.info("Fetching exchange info from Binance to create trading settings")

{:ok, %{symbols: symbols}} = binance_client.get_exchange_info()

%{
  chunks: chunks,
  budget: budget,
  buy_down_interval: buy_down_interval,
  profit_target: profit_target,
  rebuy_interval: rebuy_interval
} = Application.compile_env(:naive, :trading).defaults

timestamp = NaiveDateTime.utc_now()
  |> NaiveDateTime.truncate(:second)

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

Logger.info("Inserting default settings for symbols")

total_count = symbols
  |> Enum.map(&(%{base_settings | symbol: &1["symbol"]}))
  |> Enum.chunk_every(1000)
  |> Enum.reduce(0, fn batch, acc ->
    {count, nil} = Repo.insert_all(Settings, batch)
    Logger.info("Inserted batch of #{count} symbols")
    acc + count
  end)

Logger.info("Inserted settings for #{total_count} symbols")
