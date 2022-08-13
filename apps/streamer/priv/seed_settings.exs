require Logger

alias Streamer.Repo
alias Streamer.Schema.Settings

binance_client = Application.get_env(:streamer, :binance_client)

Logger.info("Fetching exchange info from Binance to create streaming settings")

{:ok, symbols} = binance_client.fetch_symbols()

timestamp = NaiveDateTime.utc_now()
  |> NaiveDateTime.truncate(:second)

base_settings = %{
  symbol: "",
  status: "off",
  inserted_at: timestamp,
  updated_at: timestamp
}

Logger.info("Inserting default settings for symbols")

maps = symbols
  |> Enum.map(&(%{base_settings | symbol: &1}))

{count, nil} = Repo.insert_all(Settings, maps)

Logger.info("Inserted settings for #{count} symbols")
