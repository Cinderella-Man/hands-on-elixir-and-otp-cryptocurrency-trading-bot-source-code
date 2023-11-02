defmodule Indicator.Ohlc do
  require Logger

  alias Core.Struct.TradeEvent

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

  def process([_ | _] = ohlcs, %TradeEvent{} = trade_event) do
    {old_ohlcs, new_ohlcs} = merge_prices(ohlcs, trade_event.price, trade_event.trade_time)

    old_ohlcs |> Enum.each(&maybe_broadcast/1)
    new_ohlcs
  end

  def process(symbol, %TradeEvent{} = trade_event) do
    generate_ohlcs(symbol, trade_event.price, trade_event.trade_time)
  end

  def merge_prices(ohlcs, price, trade_time) do
    results =
      ohlcs
      |> Enum.map(&merge_price(&1, price, trade_time))

    {
      results |> Enum.map(&elem(&1, 0)) |> Enum.filter(& &1),
      results |> Enum.map(&elem(&1, 1))
    }
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

  def generate_ohlcs(symbol, price, trade_time) do
    [1, 5, 15, 60, 4 * 60, 24 * 60]
    |> Enum.map(
      &generate_ohlc(
        symbol,
        &1,
        price,
        trade_time
      )
    )
  end

  def generate_ohlc(symbol, duration, price, trade_time) do
    start_time = div(div(div(trade_time, 1000), 60), duration) * duration * 60

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

    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "OHLC:#{ohlc.symbol}",
      ohlc
    )
  end
end
