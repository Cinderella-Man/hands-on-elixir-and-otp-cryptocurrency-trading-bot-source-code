require Logger

alias Streamer.Repo
alias Streamer.Schema.Settings

binance_client = Application.compile_env(:streamer, :binance_client)

Logger.info("Fetching exchange info from Binance to create streaming settings")

{:ok, %{symbols: symbols}} = binance_client.get_exchange_info()

timestamp = NaiveDateTime.utc_now()
  |> NaiveDateTime.truncate(:second)

base_settings = %{
  symbol: "",
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
