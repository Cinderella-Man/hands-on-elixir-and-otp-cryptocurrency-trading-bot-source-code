require Logger

alias Streamer.Repo
alias Streamer.Schema.Settings

exchange_client = Application.compile_env(:streamer, :exchange_client)

Logger.info("Fetching exchange info from Binance to create streaming settings")

{:ok, symbols} = exchange_client.fetch_symbols()

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
