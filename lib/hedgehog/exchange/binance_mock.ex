defmodule Hedgehog.Exchange.BinanceMock do
  use GenServer

  alias Binance.Order
  alias Binance.OrderResponse
  alias Decimal, as: D
  alias Hedgehog.Exchange.TradeEvent

  require Logger

  @type symbol :: binary
  @type quantity :: binary
  @type price :: binary
  @type time_in_force :: binary
  @type timestamp :: non_neg_integer
  @type order_id :: non_neg_integer
  @type orig_client_order_id :: binary
  @type recv_window :: binary
  @callback order_limit_buy(
              symbol,
              quantity,
              price,
              time_in_force
            ) :: {:ok, %OrderResponse{}} | {:error, term}
  @callback order_limit_sell(
              symbol,
              quantity,
              price,
              time_in_force
            ) :: {:ok, %OrderResponse{}} | {:error, term}
  @callback get_order(
              symbol,
              timestamp,
              order_id,
              orig_client_order_id | nil,
              recv_window | nil
            ) :: {:ok, %Order{}} | {:error, term}

  @use_cached_exchange_info Application.compile_env!(:hedgehog, [
                              :exchanges,
                              :binance_mock,
                              :use_cached_exchange_info
                            ])

  defmodule State do
    defstruct order_books: %{}, subscriptions: [], next_order_id: 1
  end

  defmodule OrderBook do
    defstruct buy_side: [], sell_side: [], historical: []
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %State{}}
  end

  def get_order(symbol, time, order_id) do
    GenServer.call(
      __MODULE__,
      {:get_order, symbol, time, order_id}
    )
  end

  def generate_fake_order(order_id, symbol, quantity, price, side)
      when is_binary(symbol) and
             is_binary(quantity) and
             is_number(price) and
             (side == "BUY" or side == "SELL") do
    current_timestamp = :os.system_time(:millisecond)
    client_order_id = :crypto.hash(:md5, "#{order_id}") |> Base.encode16()

    Binance.Order.new(%{
      symbol: symbol,
      order_id: order_id,
      client_order_id: client_order_id,
      price: price,
      orig_qty: quantity,
      executed_qty: "0.00000000",
      cummulative_quote_qty: "0.00000000",
      status: "NEW",
      time_in_force: "GTC",
      type: "LIMIT",
      side: side,
      stop_price: "0.00000000",
      iceberg_qty: "0.00000000",
      time: current_timestamp,
      update_time: current_timestamp,
      is_working: true
    })
  end

  def convert_order_to_order_response(%Binance.Order{} = order) do
    response = struct(Binance.OrderResponse, Map.from_struct(order))
    %{response | transact_time: order.time}
  end

  def get_exchange_info do
    case @use_cached_exchange_info do
      true -> get_cached_exchange_info()
      _ -> Binance.get_exchange_info()
    end
  end

  def order_limit_buy(symbol, quantity, price, "GTC") do
    order_limit(symbol, quantity, price, "BUY")
  end

  def order_limit_sell(symbol, quantity, price, "GTC") do
    order_limit(symbol, quantity, price, "SELL")
  end

  def handle_info(
        %TradeEvent{} = trade_event,
        %{order_books: order_books} = state
      ) do
    order_book =
      Map.get(
        order_books,
        :"#{trade_event.symbol}",
        %OrderBook{}
      )

    trade_price = D.from_float(trade_event.price)

    filled_buy_orders =
      order_book.buy_side
      |> Enum.take_while(&D.lte?(trade_price, D.from_float(&1.price)))
      |> Enum.map(&Map.replace!(&1, :status, "FILLED"))

    filled_sell_orders =
      order_book.sell_side
      |> Enum.take_while(&D.gte?(trade_price, D.from_float(&1.price)))
      |> Enum.map(&Map.replace!(&1, :status, "FILLED"))

    remaining_buy_orders =
      order_book.buy_side
      |> Enum.drop(length(filled_buy_orders))

    remaining_sell_orders =
      order_book.sell_side
      |> Enum.drop(length(filled_sell_orders))

    order_books =
      Map.replace!(
        order_books,
        :"#{trade_event.symbol}",
        %{
          buy_side: remaining_buy_orders,
          sell_side: remaining_sell_orders,
          historical:
            filled_buy_orders ++
              filled_sell_orders ++
              order_book.historical
        }
      )

    {:noreply, %{state | order_books: order_books}}
  end

  def handle_cast(
        {:add_order, %Binance.Order{symbol: symbol} = order},
        %State{
          order_books: order_books,
          subscriptions: subscriptions
        } = state
      ) do
    new_subscriptions = subscribe_to_topic(symbol, subscriptions)
    updated_order_books = add_order(order, order_books)

    {
      :noreply,
      %{
        state
        | order_books: updated_order_books,
          subscriptions: new_subscriptions
      }
    }
  end

  def handle_call(
        {:get_order, symbol, time, order_id},
        _from,
        %State{order_books: order_books} = state
      ) do
    order_book =
      Map.get(
        order_books,
        :"#{symbol}",
        %OrderBook{}
      )

    (order_book.buy_side ++
       order_book.sell_side ++
       order_book.historical)
    |> Enum.find(
      &(&1.symbol == symbol and
          &1.time == time and
          &1.order_id == order_id)
    )
    |> case do
      %Binance.Order{} = order -> {:reply, {:ok, order}, state}
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(
        :generate_id,
        _from,
        %State{next_order_id: id} = state
      ) do
    {:reply, id, %{state | next_order_id: id + 1}}
  end

  defp order_limit(symbol, quantity, price, side) do
    %Binance.Order{} =
      fake_order =
      generate_fake_order(
        GenServer.call(__MODULE__, :generate_id),
        symbol,
        quantity,
        price,
        side
      )

    GenServer.cast(
      __MODULE__,
      {:add_order, fake_order}
    )

    {:ok, convert_order_to_order_response(fake_order)}
  end

  defp subscribe_to_topic(symbol, subscriptions) do
    symbol = String.upcase(symbol)
    stream_name = "TRADE_EVENTS:#{symbol}"

    case Enum.member?(subscriptions, symbol) do
      false ->
        Logger.debug("BinanceMock subscribing to #{stream_name}")

        Phoenix.PubSub.subscribe(
          Hedgehog.PubSub,
          stream_name
        )

        [symbol | subscriptions]

      _ ->
        subscriptions
    end
  end

  defp add_order(
         %Binance.Order{symbol: symbol} = order,
         order_books
       ) do
    order_book = Map.get(order_books, :"#{symbol}", %OrderBook{})

    order_book =
      if order.side == "SELL" do
        # Sell orders are sorted ascending (lowest price first)
        updated_sell_side = insert_sorted(order, order_book.sell_side, &D.lt?/2)
        %{order_book | sell_side: updated_sell_side}
      else
        # Buy orders are sorted descending (highest price first)
        updated_buy_side = insert_sorted(order, order_book.buy_side, &D.gt?/2)
        %{order_book | buy_side: updated_buy_side}
      end

    Map.put(order_books, :"#{symbol}", order_book)
  end

  defp insert_sorted(order, orders, sorter) do
    {left, right} =
      Enum.split_while(
        orders,
        &sorter.(
          D.from_float(&1.price),
          D.from_float(order.price)
        )
      )

    left ++ [order | right]
  end

  defp get_cached_exchange_info do
    {:ok, data} =
      File.cwd!()
      |> Path.split()
      |> Kernel.++([
        "priv",
        "cache",
        "exchange_info.json"
      ])
      |> Path.join()
      |> File.read()

    {:ok, Jason.decode!(data) |> Binance.ExchangeInfo.new()}
  end
end
