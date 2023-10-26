defmodule Naive.DynamicTraderSupervisor do
  use DynamicSupervisor

  require Logger

  alias Naive.Repo
  alias Naive.Schema.Settings
  alias Naive.Strategy
  alias Naive.Trader

  import Ecto.Query, only: [from: 2]

  @registry :naive_traders

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def autostart_workers do
    Repo.all(
      from(s in Settings,
        where: s.status == "on",
        select: s.symbol
      )
    )
    |> Enum.map(&start_child/1)
  end

  def start_worker(symbol) do
    Logger.info("Starting trading on #{symbol}")
    Strategy.update_status(symbol, "on")
    start_child(symbol)
  end

  def stop_worker(symbol) do
    Logger.info("Stopping trading on #{symbol}")
    Strategy.update_status(symbol, "off")
    stop_child(symbol)
  end

  def shutdown_worker(symbol) when is_binary(symbol) do
    Logger.info("Shutdown of trading on #{symbol} initialized")
    {:ok, settings} = Strategy.update_status(symbol, "shutdown")
    Trader.notify(:settings_updated, settings)
    {:ok, settings}
  end

  defp start_child(args) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Trader, args}
    )
  end

  defp stop_child(args) do
    case Registry.lookup(@registry, args) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      _ -> Logger.warning("Unable to locate process assigned to #{inspect(args)}")
    end
  end
end
