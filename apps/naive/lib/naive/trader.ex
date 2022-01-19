defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Core.Struct.TradeEvent

  require Logger

  @binance_client Application.compile_env(:naive, :binance_client)
  @leader Application.get_env(:naive, :leader)
  @logger Application.get_env(:core, :logger)
  @pubsub_client Application.get_env(:core, :pubsub_client)

  defmodule State do
    @enforce_keys [
      :id,
      :symbol,
      :budget,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]
    defstruct [
      :id,
      :symbol,
      :budget,
      :buy_order,
      :sell_order,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]
  end

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{id: id, symbol: symbol} = state) do
    symbol = String.upcase(symbol)

    @logger.info("Initializing new trader(#{id}) for #{symbol}")

    @pubsub_client.subscribe(
      Core.PubSub,
      "TRADE_EVENTS:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(%TradeEvent{} = trade_event, %State{} = state) do
    Naive.Strategy.generate_decision(trade_event, state)
    |> execute_decision(state)
  end

  def execute_decision(
        {:place_buy_order, price, quantity},
        %State{
          id: id,
          symbol: symbol
        } = state
      ) do
    @logger.info(
      "The trader(#{id}) is placing a BUY order " <>
        "for #{symbol} @ #{price}, quantity: #{quantity}"
    )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_buy(symbol, quantity, price, "GTC")

    :ok = broadcast_order(order)

    new_state = %{state | buy_order: order}
    @leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def execute_decision(
        {:place_sell_order, sell_price},
        %State{
          id: id,
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            orig_qty: quantity
          }
        } = state
      ) do
    @logger.info(
      "The trader(#{id}) is placing a SELL order for " <>
        "#{symbol} @ #{sell_price}, quantity: #{quantity}."
    )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_sell(symbol, quantity, sell_price, "GTC")

    :ok = broadcast_order(order)

    new_state = %{state | sell_order: order}
    @leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def execute_decision(
        :fetch_buy_order,
        %State{
          id: id,
          symbol: symbol,
          buy_order:
            %Binance.OrderResponse{
              order_id: order_id,
              transact_time: timestamp
            } = buy_order
        } = state
      ) do
    {:ok, %Binance.Order{} = current_buy_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    :ok = broadcast_order(current_buy_order)

    buy_order = %{buy_order | status: current_buy_order.status}

    @logger.info("Trader's(#{id} #{symbol} buy order got partially filled")
    new_state = %{state | buy_order: buy_order}

    @leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def execute_decision(
        :exit,
        %State{
          id: id,
          symbol: symbol
        } = state
      ) do
    @logger.info("Trader(#{id}) finished trade cycle for #{symbol}")
    {:stop, :normal, state}
  end

  def execute_decision(
        :fetch_sell_order,
        %State{
          id: id,
          symbol: symbol,
          sell_order:
            %Binance.OrderResponse{
              order_id: order_id,
              transact_time: timestamp
            } = sell_order
        } = state
      ) do
    {:ok, %Binance.Order{} = current_sell_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    :ok = broadcast_order(current_sell_order)

    sell_order = %{sell_order | status: current_sell_order.status}

    @logger.info("Trader's(#{id} #{symbol} SELL order got partially filled")
    new_state = %{state | sell_order: sell_order}
    {:noreply, new_state}
  end

  def execute_decision(
        :rebuy,
        %State{
          id: id,
          symbol: symbol
        } = state
      ) do
    @logger.info("Rebuy triggered for #{symbol} by the trader(#{id})")
    new_state = %{state | rebuy_notified: true}
    @leader.notify(:rebuy_triggered, new_state)
    {:noreply, new_state}
  end

  def execute_decision(:skip, state) do
    {:noreply, state}
  end

  defp broadcast_order(%Binance.OrderResponse{} = response) do
    response
    |> convert_to_order()
    |> broadcast_order()
  end

  defp broadcast_order(%Binance.Order{} = order) do
    @pubsub_client.broadcast(
      Core.PubSub,
      "ORDERS:#{order.symbol}",
      order
    )
  end

  defp convert_to_order(%Binance.OrderResponse{} = response) do
    data =
      response
      |> Map.from_struct()

    struct(Binance.Order, data)
    |> Map.merge(%{
      cummulative_quote_qty: "0.00000000",
      stop_price: "0.00000000",
      iceberg_qty: "0.00000000",
      is_working: true
    })
  end
end
