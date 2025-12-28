defmodule Streamer.Binance do
  use WebSockex

  require Logger

  @stream_endpoint "wss://stream.binance.com:9443/ws/"

  def start_link(symbol) do
    Logger.info(
      "Binance streamer is connecting to websocket " <>
        "stream for #{symbol} trade events"
    )

    WebSockex.start_link(
      "#{@stream_endpoint}#{String.downcase(symbol)}@trade",
      __MODULE__,
      nil,
      name: via_tuple(symbol)
    )
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} -> process_event(event)
      {:error, _} -> Logger.error("Unable to parse msg: #{msg}")
    end

    {:ok, state}
  end

  defp process_event(%{"e" => "trade"} = event) do
    {trade_price, ""} = Float.parse(event["p"])

    trade_event = %Core.Struct.TradeEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :trade_id => event["t"],
      :price => trade_price,
      :quantity => event["q"],
      :trade_time => event["T"],
      :buyer_market_maker => event["m"]
    }

    Logger.debug(
      "Trade event received " <>
        "#{trade_event.symbol}@#{trade_event.price}"
    )

    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "TRADE_EVENTS:#{trade_event.symbol}",
      trade_event
    )
  end

  defp via_tuple(symbol) do
    {:via, Registry, {:binance_streamers, String.upcase(symbol)}}
  end
end
