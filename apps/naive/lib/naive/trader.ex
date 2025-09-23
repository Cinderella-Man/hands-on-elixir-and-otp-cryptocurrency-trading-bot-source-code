defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Decimal, as: D
  alias Streamer.Binance.TradeEvent

  require Logger

  @binance_client Application.compile_env(:naive, :binance_client)

  defmodule State do
    @enforce_keys [:symbol, :profit_target, :tick_size]
    defstruct [
      :symbol,
      :buy_order,
      :sell_order,
      :profit_target,
      :tick_size
    ]
  end

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{symbol: symbol} = state) do
    symbol = String.upcase(symbol)

    Logger.info("Initializing new trader for #{symbol}")

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "TRADE_EVENTS:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(
        %TradeEvent{price: price},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    quantity = "100"

    Logger.info("Placing BUY order for #{symbol} @ #{price}, quantity: #{quantity}")

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
      "Buy order filled, placing SELL order for " <>
        "#{symbol} @ #{sell_price}, quantity: #{quantity}"
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

    Logger.info("Trade finished, trader will now exit")
    new_state = %{state | sell_order: sell_order_response}
    Naive.Leader.notify(:trader_state_updated, new_state)
    {:stop, :normal, new_state}
  end

  def handle_info(%TradeEvent{}, state) do
    {:noreply, state}
  end

  defp calculate_sell_price(buy_price, profit_target, tick_size) do
    fee = "1.001"

    original_price = D.mult(D.from_float(buy_price), fee)

    net_target_price =
      D.mult(
        original_price,
        D.add("1.0", profit_target)
      )

    gross_target_price = D.mult(net_target_price, fee)

    D.to_float(
      D.mult(
        D.div_int(gross_target_price, tick_size),
        tick_size
      )
    )
  end

  defp convert_order_to_order_response(%Binance.Order{} = order) do
    response = struct(Binance.OrderResponse, Map.from_struct(order))
    %{response | transact_time: order.time}
  end
end
