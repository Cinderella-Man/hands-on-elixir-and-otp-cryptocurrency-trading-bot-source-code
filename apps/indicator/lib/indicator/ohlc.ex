defmodule Indicator.Ohlc do
  alias Core.Struct.TradeEvent

  require Logger

  @pubsub_client Application.get_env(:core, :pubsub_client)

  @enforce_keys [
    :symbol,
    :start_time,
    :duration
  ]
  defstruct [
    :symbol,
    :start_time,
    :duration,
    :open,
    :high,
    :low,
    :close
  ]

  def process(%__MODULE__{} = ohlc, %TradeEvent{} = trade_event) do
    {old_ohlc, new_ohlc} = merge_price(ohlc, trade_event.price, trade_event.trade_time)
    maybe_broadcast(old_ohlc)
    new_ohlc
  end

  def process({symbol, duration}, %TradeEvent{} = trade_event) do
    generate_ohlc(symbol, duration, trade_event.price, trade_event.trade_time)
  end

  def merge_price(%__MODULE__{} = ohlc, price, trade_time) do
    if within_current_timeframe(ohlc.start_time, ohlc.duration, trade_time) do
      {nil, %{ohlc | low: min(ohlc.low, price), high: max(ohlc.high, price), close: price}}
    else
      {ohlc, generate_ohlc(ohlc.symbol, ohlc.duration, price, trade_time)}
    end
  end

  def within_current_timeframe(start_time, duration, trade_time) do
    end_time = start_time + duration * 60
    trade_time = div(trade_time, 1000)

    start_time <= trade_time && trade_time < end_time
  end

  def generate_ohlc(symbol, duration, price, trade_time) do
    start_time = div(div(trade_time, 1000), 60) * 60

    %__MODULE__{
      symbol: symbol,
      start_time: start_time,
      duration: duration,
      open: price,
      high: price,
      low: price,
      close: price
    }
  end

  defp maybe_broadcast(nil), do: :ok

  defp maybe_broadcast(%__MODULE__{} = ohlc) do
    Logger.debug("Broadcasting OHLC: #{inspect(ohlc)}")

    @pubsub_client.broadcast(
      Core.PubSub,
      "OHLC:#{ohlc.symbol}",
      ohlc
    )
  end
end
