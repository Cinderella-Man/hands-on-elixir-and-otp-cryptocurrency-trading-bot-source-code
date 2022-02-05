defmodule Indicator do
  @moduledoc """
  Documentation for `Indicator`.
  """

  def aggregate_ohlcs(symbol) do
    [1, 5, 15, 60, 4 * 60, 24 * 60]
    |> Enum.each(&DynamicSupervisor.start_child(
      Indicator.DynamicSupervisor,
      {Indicator.Ohlc.Worker, {symbol, &1}}
    ))
  end
end
