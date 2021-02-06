defmodule Naive.Leader do
  use GenServer

  alias Decimal, as: D
  alias Naive.Repo
  alias Naive.Schema.Settings
  alias Naive.Trader

  require Logger

  @binance_client Application.get_env(:naive, :binance_client)

  defmodule State do
    defstruct symbol: nil,
              settings: nil,
              traders: []
  end

  defmodule TraderData do
    defstruct pid: nil,
              ref: nil,
              state: nil
  end

  def start_link(symbol) do
    GenServer.start_link(
      __MODULE__,
      symbol,
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def init(symbol) do
    {:ok,
     %State{
       symbol: symbol
     }, {:continue, :start_traders}}
  end

  def notify(:trader_state_updated, trader_state) do
    GenServer.call(
      :"#{__MODULE__}-#{trader_state.symbol}",
      {:update_trader_state, trader_state}
    )
  end

  def notify(:rebuy_triggered, trader_state) do
    GenServer.call(
      :"#{__MODULE__}-#{trader_state.symbol}",
      {:rebuy_triggered, trader_state}
    )
  end

  def notify(:settings_updated, settings) do
    GenServer.call(
      :"#{__MODULE__}-#{settings.symbol}",
      {:update_settings, settings}
    )
  end

  def handle_continue(:start_traders, %{symbol: symbol} = state) do
    settings = fetch_symbol_settings(symbol)
    trader_state = fresh_trader_state(settings)
    traders = [start_new_trader(trader_state)]

    {:noreply, %{state | settings: settings, traders: traders}}
  end

  def handle_call(
        {:update_trader_state, new_trader_state},
        {trader_pid, _},
        %{traders: traders} = state
      ) do
    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn("Tried to update the state of trader that leader is not aware of")
        {:reply, :ok, state}

      index ->
        old_trader_data = Enum.at(traders, index)
        new_trader_data = %{old_trader_data | :state => new_trader_state}

        {:reply, :ok, %{state | :traders => List.replace_at(traders, index, new_trader_data)}}
    end
  end

  def handle_call(
        {:rebuy_triggered, new_trader_state},
        {trader_pid, _},
        %{traders: traders, symbol: symbol, settings: settings} = state
      ) do
    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn("Rebuy triggered by trader that leader is not aware of")
        {:reply, :ok, state}

      index ->
        traders =
          if settings.chunks == length(traders) do
            Logger.info("All traders already started for #{symbol}")
            traders
          else
            if settings.status == "shutdown" do
              Logger.warn(
                "The leader won't start a new trader on #{symbol} " <>
                  "as symbol is in the 'shutdown' state"
              )

              traders
            else
              Logger.info("Starting new trader for #{symbol}")
              [start_new_trader(fresh_trader_state(settings)) | traders]
            end
          end

        old_trader_data = Enum.at(traders, index)
        new_trader_data = %{old_trader_data | :state => new_trader_state}
        new_traders = List.replace_at(traders, index, new_trader_data)

        {:reply, :ok, %{state | :traders => new_traders}}
    end
  end

  def handle_call(
        {:update_settings, new_settings},
        _,
        state
      ) do
    {:reply, :ok, %{state | settings: new_settings}}
  end

  def handle_info(
        {:DOWN, _ref, :process, trader_pid, :normal},
        %{traders: traders, symbol: symbol, settings: settings} = state
      ) do
    Logger.info("#{symbol} trader finished trade - restarting")

    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn(
          "Tried to restart finished #{symbol} " <>
            "trader that leader is not aware of"
        )

        if settings.status == "shutdown" and traders == [] do
          Naive.stop_trading(state.symbol)
        end

        {:noreply, state}

      index ->
        new_traders =
          if settings.status == "shutdown" do
            Logger.warn(
              "The leader won't start a new trader on #{symbol} " <>
                "as symbol is in shutdown state"
            )

            if length(traders) == 1 do
              Naive.stop_trading(state.symbol)
            end

            List.delete_at(traders, index)
          else
            new_trader_data = start_new_trader(fresh_trader_state(settings))
            List.replace_at(traders, index, new_trader_data)
          end

        {:noreply, %{state | traders: new_traders}}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, trader_pid, _reason},
        %{traders: traders, symbol: symbol} = state
      ) do
    Logger.error("#{symbol} trader died - trying to restart")

    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn(
          "Tried to restart #{symbol} trader " <>
            "but failed to find its cached state"
        )

        {:noreply, state}

      index ->
        trader_data = Enum.at(traders, index)
        new_trader_data = start_new_trader(trader_data.state)
        new_traders = List.replace_at(traders, index, new_trader_data)

        {:noreply, %{state | traders: new_traders}}
    end
  end

  defp fresh_trader_state(settings) do
    %{
      struct(Trader.State, settings)
      | id: :os.system_time(:millisecond),
        budget: D.div(settings.budget, settings.chunks),
        rebuy_notified: false
    }
  end

  defp fetch_symbol_settings(symbol) do
    symbol_filters = fetch_symbol_filters(symbol)
    settings = Repo.get_by!(Settings, symbol: symbol)

    Map.merge(
      symbol_filters,
      settings |> Map.from_struct()
    )
  end

  defp fetch_symbol_filters(symbol) do
    symbol_filters =
      @binance_client.get_exchange_info()
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == symbol))
      |> Map.get("filters")

    tick_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
      |> Map.get("tickSize")
      |> Decimal.new()

    step_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "LOT_SIZE"))
      |> Map.get("stepSize")
      |> Decimal.new()

    %{
      tick_size: tick_size,
      step_size: step_size
    }
  end

  defp start_new_trader(%Trader.State{} = state) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        :"Naive.DynamicTraderSupervisor-#{state.symbol}",
        {Naive.Trader, state}
      )

    ref = Process.monitor(pid)

    %TraderData{pid: pid, ref: ref, state: state}
  end
end
