defmodule Hedgehog.Data.Collector do
  @moduledoc """
  Documentation for `Hedgehog.Data.Collector`.
  """

  alias Hedgehog.Data.Collector.DynamicWorkerSupervisor

  def start_storing(stream, symbol) do
    to_topic(stream, symbol)
    |> DynamicWorkerSupervisor.start_worker()
  end

  def stop_storing(stream, symbol) do
    to_topic(stream, symbol)
    |> DynamicWorkerSupervisor.stop_worker()
  end

  defp to_topic(stream, symbol) do
    [stream, symbol]
    |> Enum.map(&String.upcase/1)
    |> Enum.join(":")
  end
end
