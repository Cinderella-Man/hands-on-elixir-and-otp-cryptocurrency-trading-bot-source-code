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

  def notify(:settings_updated, settings) do
    call_trader(settings.symbol, {:update_settings, settings})
  end

  def handle_call(
        {:update_settings, new_settings},
        _,
        state
      ) do
    {:reply, :ok, %{state | settings: new_settings}}
  end

  def handle_info(%TradeEvent{} = trade_event, %State{} = state) do
    case Naive.Strategy.execute(trade_event, state.positions, state.settings) do
      {:ok, updated_positions} ->
        {:noreply, %{state | positions: updated_positions}}

      :exit ->
        {:ok, _settings} = Strategy.update_status(trade_event.symbol, "off")
        Logger.info("Trading for #{trade_event.symbol} stopped")
        {:stop, :normal, state}
    end
  end

  defp call_trader(symbol, data) do
    case Registry.lookup(@registry, symbol) do
      [{pid, _}] ->
        GenServer.call(
          pid,
          data
        )

      _ ->
        Logger.warn("Unable to locate trader process assigned to #{symbol}")
        {:error, :unable_to_locate_trader}
    end
  end

  defp via_tuple(symbol) do
    {:via, Registry, {@registry, symbol}}
  end
end
