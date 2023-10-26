defmodule BinanceMock do
  @behaviour Core.Exchange
  use GenServer

  alias Core.Exchange
  alias Core.Struct.TradeEvent
  alias Decimal, as: D

  require Logger

  defmodule State do
    defstruct order_books: %{}, subscriptions: [], fake_order_id: 1
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

  def order_limit_buy(symbol, quantity, price) do
    order_limit(symbol, quantity, price, "BUY")
  end

  def order_limit_sell(symbol, quantity, price) do
    order_limit(symbol, quantity, price, "SELL")
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
             is_binary(price) and
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

  defp side_to_atom("BUY"), do: :buy
  # <= added
  # <= added
  defp side_to_atom("SELL"), do: :sell
  defp status_to_atom("NEW"), do: :new
  # <= added
  # <= added
  defp status_to_atom("FILLED"), do: :filled

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
        :generate_id,
        _from,
        %State{fake_order_id: id} = state
      ) do
    {:reply, id + 1, %{state | fake_order_id: id + 1}}
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

    result =
      (order_book.buy_side ++
         order_book.sell_side ++
         order_book.historical)
      |> Enum.find(
        &(&1.symbol == symbol and
            &1.timestamp == time and
            &1.id == order_id)
      )

    {:reply, {:ok, result}, state}
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

    filled_buy_orders =
      order_book.buy_side
      |> Enum.take_while(&D.lt?(trade_event.price, &1.price))
      |> Enum.map(&Map.replace!(&1, :status, :filled))

    filled_sell_orders =
      order_book.sell_side
      |> Enum.take_while(&D.gt?(trade_event.price, &1.price))
      |> Enum.map(&Map.replace!(&1, :status, :filled))

    (filled_buy_orders ++ filled_sell_orders)
    |> Enum.map(&convert_order_to_event(&1, trade_event.event_time))
    |> Enum.each(&broadcast_trade_event/1)

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
    order_book =
      Map.get(
        order_books,
        :"#{symbol}",
        %OrderBook{}
      )

    order_book =
      if order.side == "SELL" do
        Map.replace!(
          order_book,
          :sell_side,
          [order | order_book.sell_side]
          |> Enum.sort(&D.lt?(&1.price, &2.price))
        )
      else
        Map.replace!(
          order_book,
          :buy_side,
          [order | order_book.buy_side]
          |> Enum.sort(&D.gt?(&1.price, &2.price))
        )
      end

    Map.put(order_books, :"#{symbol}", order_book)
  end

  defp convert_order_to_event(%Exchange.Order{} = order, time) do
    %TradeEvent{
      event_time: time - 1,
      symbol: order.symbol,
      trade_id: Integer.floor_div(time, 1000),
      price: order.price,
      quantity: order.quantity,
      buyer_order_id: order.id,
      seller_order_id: order.id,
      trade_time: time - 1,
      buyer_market_maker: false
    }
  end

  defp broadcast_trade_event(%TradeEvent{} = trade_event) do
    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "TRADE_EVENTS:#{trade_event.symbol}",
      trade_event
    )
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
end
