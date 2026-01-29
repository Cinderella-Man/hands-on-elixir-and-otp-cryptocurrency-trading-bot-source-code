defmodule Streamer.Binance.TradeEvent do
  @type t :: %__MODULE__{
          event_type: String.t(),
          event_time: integer(),
          symbol: String.t(),
          trade_id: integer(),
          price: float(),
          quantity: String.t(),
          trade_time: integer(),
          buyer_market_maker: boolean()
        }

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
