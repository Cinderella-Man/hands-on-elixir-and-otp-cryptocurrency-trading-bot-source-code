defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Core.Struct.TradeEvent
  alias Naive.Strategy

  require Logger

  @logger Application.compile_env(:core, :logger)
  @pubsub_client Application.compile_env(:core, :pubsub_client)
  @registry :naive_traders

  defmodule State do
    @enforce_keys [:settings, :positions]
    defstruct [:settings, positions: []]
  end

  def start_link(symbol) do
    symbol = String.upcase(symbol)

    GenServer.start_link(
      __MODULE__,
      symbol,
      name: via_tuple(symbol)
    )
  end

  def init(symbol) do
    @logger.info("Initializing new trader for #{symbol}")

    @pubsub_client.subscribe(
      Core.PubSub,
      "TRADE_EVENTS:#{symbol}"
    )

    {:ok, nil, {:continue, {:start_position, symbol}}}
  end

  def handle_continue({:start_position, symbol}, _state) do
    settings = Strategy.fetch_symbol_settings(symbol)
    positions = [Strategy.generate_fresh_position(settings)]

    {:noreply, %State{settings: settings, positions: positions}}
  end

  def handle_info(%TradeEvent{} = trade_event, %State{} = state) do
    case Naive.Strategy.execute(trade_event, state.positions, state.settings) do
      {:ok, updated_positions} ->
        {:noreply, %{state | positions: updated_positions}}

      :exit ->
        {:stop, :normal, state}
    end
  end

  defp via_tuple(symbol) do
    {:via, Registry, {@registry, symbol}}
  end
end
