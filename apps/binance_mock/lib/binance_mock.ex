defmodule BinanceMock do
  use GenServer

  @behaviour Core.Exchange

  alias Core.Exchange
  alias Core.Struct.TradeEvent
  alias Decimal, as: D

  require Logger

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

    %Exchange.Order{
      id: order_id,
      symbol: symbol,
      price: price,
      quantity: quantity,
      side: side_to_atom(side),
      status: status_to_atom("NEW"),
      timestamp: current_timestamp
    }
  end

  def order_limit_buy(symbol, quantity, price) do
    order_limit(symbol, quantity, price, "BUY")
  end

  def order_limit_sell(symbol, quantity, price) do
    order_limit(symbol, quantity, price, "SELL")
  end

  def order_limit_buy(symbol, quantity, price, "GTC") do
    order_limit(symbol, quantity, price, "BUY")
  end

  def order_limit_sell(symbol, quantity, price, "GTC") do
    order_limit(symbol, quantity, price, "SELL")
  end

  def fetch_symbols() do
    case fetch_exchange_info() do
      {:ok, %{symbols: symbols}} ->
        symbols
        |> Enum.map(& &1["symbol"])
        |> then(&{:ok, &1})

      error ->
        error
    end
  end

  def fetch_symbol_filters(symbol) do
    case fetch_exchange_info() do
      {:ok, exchange_info} ->
        {:ok, fetch_symbol_filters(symbol, exchange_info)}

      error ->
        error
    end
  end

  defp fetch_exchange_info() do
    case Application.get_env(:binance_mock, :use_cached_exchange_info) do
      true ->
        get_cached_exchange_info()

      _ ->
        Binance.get_exchange_info()
    end
  end

  defp get_cached_exchange_info do
    File.cwd!()
    |> Path.split()
    |> Enum.drop(-1)
    |> Kernel.++([
      "binance_mock",
      "test",
      "assets",
      "exchange_info.json"
    ])
    |> Path.join()
    |> File.read()
  end

  defp fetch_symbol_filters(symbol, exchange_info) do
    symbol_filters =
      exchange_info
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == symbol))
      |> Map.get("filters")

    tick_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
      |> Map.get("tickSize")

    step_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "LOT_SIZE"))
      |> Map.get("stepSize")

    %Exchange.SymbolInfo{
      symbol: symbol,
      tick_size: tick_size,
      step_size: step_size
    }
  end

  def handle_info(
        %TradeEvent{} = trade_event,
        %{order_books: order_books} = state
      ) do
    order_book =
      Map.get(
        order_books,
        trade_event.symbol,
        %OrderBook{}
      )

    trade_price = D.from_float(trade_event.price)

    {to_fill_buy_orders, remaining_buy_orders} =
      order_book.buy_side
      |> Enum.split_while(&D.lte?(trade_price, D.from_float(&1.price)))

    {to_fill_sell_orders, remaining_sell_orders} =
      order_book.sell_side
      |> Enum.split_while(&D.gte?(trade_price, D.from_float(&1.price)))

    filled_orders =
      (to_fill_buy_orders ++ to_fill_sell_orders)
      |> Enum.map(&Map.replace!(&1, :status, :filled))

    order_books =
      Map.put(
        order_books,
        trade_event.symbol,
        %{
          buy_side: remaining_buy_orders,
          sell_side: remaining_sell_orders,
          historical: filled_orders ++ order_book.historical
        }
      )

    {:noreply, %{state | order_books: order_books}}
  end

  def handle_cast(
        {:add_order, %Exchange.Order{symbol: symbol} = order},
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
        symbol,
        %OrderBook{}
      )

    (order_book.buy_side ++
       order_book.sell_side ++
       order_book.historical)
    |> Enum.find(
      &(&1.symbol == symbol and
          &1.timestamp == time and
          &1.id == order_id)
    )
    |> case do
      %Exchange.Order{} = order -> {:reply, {:ok, order}, state}
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
    %Exchange.Order{} =
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

    {:ok, fake_order}
  end

  defp subscribe_to_topic(symbol, subscriptions) do
    symbol = String.upcase(symbol)
    stream_name = "TRADE_EVENTS:#{symbol}"

    case Enum.member?(subscriptions, symbol) do
      false ->
        Logger.debug("BinanceMock subscribing to #{stream_name}")

        Phoenix.PubSub.subscribe(
          Core.PubSub,
          stream_name
        )

        [symbol | subscriptions]

      _ ->
        subscriptions
    end
  end

  defp add_order(
         %Exchange.Order{symbol: symbol} = order,
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

  defp side_to_atom("BUY"), do: :buy
  defp side_to_atom("SELL"), do: :sell

  defp status_to_atom("NEW"), do: :new
  defp status_to_atom("FILLED"), do: :filled
end
