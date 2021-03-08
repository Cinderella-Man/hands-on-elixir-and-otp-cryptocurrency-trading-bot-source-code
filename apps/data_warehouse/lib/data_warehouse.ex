defmodule DataWarehouse do
  @moduledoc """
  Documentation for `DataWarehouse`.
  """
  alias DataWarehouse.Subscriber.DynamicSupervisor

  def start_storing(stream, symbol) do
    DynamicSupervisor.start_worker("#{String.downcase(stream)}:#{String.upcase(symbol)}")
  end

  def stop_storing(stream, symbol) do
    DynamicSupervisor.stop_worker("#{String.downcase(stream)}:#{String.upcase(symbol)}")
  end
end
