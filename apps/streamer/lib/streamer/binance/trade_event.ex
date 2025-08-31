defmodule Streamer.Binance.TradeEvent do
  defstruct [
    :event_type,
    :event_time,
    :symbol,
    :trade_id,
    :price,
    :quantity,
    :trade_time,
    :buyer_market_maker
  ]
end
