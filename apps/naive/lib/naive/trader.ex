defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Decimal, as: D
  alias Streamer.Binance.TradeEvent

  require Logger

  @binance_client Application.compile_env(:naive, :binance_client)

  defmodule State do
    @enforce_keys [
      :id,
      :symbol,
      :budget,
      :buy_down_interval,
      :profit_target,
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
      :profit_target,
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

    Logger.info("Initializing new trader(#{id}) for #{symbol}")

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "TRADE_EVENTS:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(
        %TradeEvent{price: price},
        %State{
          id: id,
          symbol: symbol,
          budget: budget,
          buy_order: nil,
          buy_down_interval: buy_down_interval,
          tick_size: tick_size,
          step_size: step_size
        } = state
      ) do
    price = calculate_buy_price(price, buy_down_interval, tick_size)
    quantity = calculate_quantity(budget, price, step_size)

    Logger.info(
      "The trader(#{id}) is placing a BUY order " <>
        "for #{symbol} @ #{price}, quantity: #{quantity}"
    )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_buy(symbol, quantity, price, "GTC")

    new_state = %{state | buy_order: order}
    Naive.Leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def handle_info(
        %TradeEvent{
          price: trade_price
        },
        %State{
          id: id,
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price,
            order_id: order_id,
            orig_qty: quantity,
            transact_time: timestamp
          },
          sell_order: nil,
          profit_target: profit_target,
          tick_size: tick_size
        } = state
      )
      when trade_price <= buy_price do
    {:ok, %Binance.Order{} = current_buy_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    buy_order_response = convert_order_to_order_response(current_buy_order)
    sell_price = calculate_sell_price(buy_price, profit_target, tick_size)

    Logger.info(
      "The trader(#{id}) is placing a SELL order for " <>
        "#{symbol} @ #{sell_price}, quantity: #{quantity}."
    )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_sell(symbol, quantity, sell_price, "GTC")

    new_state = %{state | buy_order: buy_order_response, sell_order: order}
    Naive.Leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def handle_info(
        %TradeEvent{
          price: trade_price
        },
        %State{
          id: id,
          symbol: symbol,
          sell_order: %Binance.OrderResponse{
            price: sell_price,
            order_id: order_id,
            transact_time: timestamp
          }
        } = state
      )
      when trade_price >= sell_price do
    {:ok, %Binance.Order{} = current_sell_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    sell_order_response = convert_order_to_order_response(current_sell_order)
    Logger.info("Trader(#{id}) finished trade cycle for #{symbol}")
    new_state = %{state | sell_order: sell_order_response}
    Naive.Leader.notify(:trader_state_updated, new_state)
    {:stop, :normal, new_state}
  end

  def handle_info(
        %TradeEvent{
          price: current_price
        },
        %State{
          id: id,
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        } = state
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) do
      Logger.info("Rebuy triggered for #{symbol} by the trader(#{id})")
      new_state = %{state | rebuy_notified: true}
      Naive.Leader.notify(:rebuy_triggered, new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(%TradeEvent{}, state) do
    {:noreply, state}
  end

  defp convert_order_to_order_response(%Binance.Order{} = order) do
    response = struct(Binance.OrderResponse, Map.from_struct(order))
    %{response | transact_time: order.time}
  end

  defp calculate_sell_price(buy_price, profit_target, tick_size) do
    fee = D.new("1.001")

    buy_price
    |> D.from_float()
    |> D.mult(fee)
    |> D.mult(D.add(D.new(1), profit_target))
    |> D.mult(fee)
    |> D.div_int(tick_size)
    |> D.mult(tick_size)
    |> D.to_float()
  end

  defp calculate_buy_price(current_price, buy_down_interval, tick_size) do
    current_price = D.from_float(current_price)

    exact_buy_price =
      D.sub(
        current_price,
        D.mult(current_price, buy_down_interval)
      )

    exact_buy_price
    |> D.div_int(tick_size)
    |> D.mult(tick_size)
    |> D.to_float()
  end

  defp calculate_quantity(budget, price, step_size) do
    budget
    |> D.div(D.from_float(price))
    |> D.div_int(step_size)
    |> D.mult(step_size)
    |> D.to_string(:normal)
  end

  defp trigger_rebuy?(buy_price, current_price, rebuy_interval) do
    buy_price = Decimal.from_float(buy_price)
    current_price = Decimal.from_float(current_price)

    rebuy_price =
      D.sub(
        buy_price,
        D.mult(buy_price, rebuy_interval)
      )

    D.lt?(current_price, rebuy_price)
  end
end
