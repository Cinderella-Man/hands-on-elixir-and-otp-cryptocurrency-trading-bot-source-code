defmodule Indicator do
  @moduledoc """
  Documentation for `Indicator`.
  """

  def aggregate_ohlcs(symbol) do
    DynamicSupervisor.start_child(
      Indicator.DynamicSupervisor,
      {Indicator.Ohlc.Worker, symbol}
    )
  end
end
