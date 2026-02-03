defmodule Naive.Trader do
  use GenServer

  alias Decimal, as: D
  alias Streamer.Binance.TradeEvent

  require Logger

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

  def start_link(%{} = args) do
    GenServer.start_link(__MODULE__, args, name: :trader)
  end

  def init(%{symbol: symbol, profit_target: profit_target}) do
    symbol = String.upcase(symbol)

    Logger.info("Initializing new trader for #{symbol}")

    {:ok,
     %State{
       symbol: symbol,
       profit_target: profit_target,
       tick_size: nil
     }, {:continue, :fetch_tick_size}}
  end

  def handle_continue(:fetch_tick_size, %State{symbol: symbol} = state) do
    tick_size = fetch_tick_size(symbol)

    {:noreply, %{state | tick_size: tick_size}}
  end

  def handle_cast(
        %TradeEvent{price: price},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    quantity = "100"
    Logger.info("Placing BUY order for #{symbol} @ #{price}, quantity: #{quantity}")

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_buy(symbol, quantity, price, "GTC")

    {:noreply, %{state | buy_order: order}}
  end

  def handle_cast(
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
      Binance.get_order(
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
      Binance.order_limit_sell(symbol, quantity, sell_price, "GTC")

    {:noreply, %{state | buy_order: buy_order_response, sell_order: order}}
  end

  def handle_cast(
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
      Binance.get_order(
        symbol,
        timestamp,
        order_id
      )

    sell_order_response = convert_order_to_order_response(current_sell_order)
    Logger.info("Trade finished, trader will now exit")
    {:stop, :normal, %{state | sell_order: sell_order_response}}
  end

  def handle_cast(%TradeEvent{}, state) do
    {:noreply, state}
  end

  defp fetch_tick_size(symbol) do
    {:ok, exchange_info} = Binance.get_exchange_info()

    exchange_info
    |> Map.get(:symbols)
    |> Enum.find(&(&1["symbol"] == symbol))
    |> Map.get("filters")
    |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
    |> Map.get("tickSize")
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
end
