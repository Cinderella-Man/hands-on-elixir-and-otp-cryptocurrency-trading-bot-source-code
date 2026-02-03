defmodule Hedgehog.Strategy.Naive.Formula do
  alias Decimal, as: D
  alias Hedgehog.Exchange.TradeEvent
  alias Hedgehog.Repo
  alias Hedgehog.Strategy.Naive.Settings

  @binance_client Application.compile_env(:hedgehog, :binance_client)

  require Logger

  defmodule Position do
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

  def execute(%TradeEvent{} = trade_event, positions, settings) do
    generate_decisions(positions, [], trade_event, settings)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings) end)
    end)
    |> Task.await_many()
    |> then(&parse_results/1)
  end

  def generate_decisions([], generated_results, _trade_event, _settings) do
    generated_results
  end

  def generate_decisions([position | rest] = positions, generated_results, trade_event, settings) do
    current_positions = positions ++ (generated_results |> Enum.map(&elem(&1, 0)))

    case generate_decision(trade_event, position, current_positions, settings) do
      :exit ->
        generate_decisions(rest, generated_results, trade_event, settings)

      :rebuy ->
        generate_decisions(
          rest,
          [{:skip, %{position | rebuy_notified: true}}, {:rebuy, position}] ++ generated_results,
          trade_event,
          settings
        )

      decision ->
        generate_decisions(
          rest,
          [{decision, position} | generated_results],
          trade_event,
          settings
        )
    end
  end

  def generate_decision(
        %TradeEvent{price: price},
        %Position{
          budget: budget,
          buy_order: nil,
          buy_down_interval: buy_down_interval,
          tick_size: tick_size,
          step_size: step_size
        },
        _positions,
        _settings
      ) do
    price = calculate_buy_price(price, buy_down_interval, tick_size)
    quantity = calculate_quantity(budget, price, step_size)

    {:place_buy_order, price, quantity}
  end

  def generate_decision(
        %TradeEvent{},
        %Position{
          buy_order: %Binance.OrderResponse{
            price: buy_price,
            status: "FILLED"
          },
          sell_order: nil,
          profit_target: profit_target,
          tick_size: tick_size
        },
        _positions,
        _settings
      ) do
    sell_price = calculate_sell_price(buy_price, profit_target, tick_size)

    {:place_sell_order, sell_price}
  end

  def generate_decision(
        %TradeEvent{
          price: trade_price
        },
        %Position{
          buy_order: %Binance.OrderResponse{
            price: buy_price
          },
          sell_order: nil
        },
        _positions,
        _settings
      )
      when trade_price <= buy_price do
    :fetch_buy_order
  end

  def generate_decision(
        %TradeEvent{},
        %Position{
          sell_order: %Binance.OrderResponse{
            status: "FILLED"
          }
        },
        _positions,
        settings
      ) do
    if settings.status != "shutdown" do
      :finished
    else
      :exit
    end
  end

  def generate_decision(
        %TradeEvent{
          price: trade_price
        },
        %Position{
          sell_order: %Binance.OrderResponse{
            price: sell_price
          }
        },
        _positions,
        _settings
      )
      when trade_price >= sell_price do
    :fetch_sell_order
  end

  def generate_decision(
        %TradeEvent{
          price: current_price
        },
        %Position{
          buy_order: %Binance.OrderResponse{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        },
        positions,
        settings
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) &&
         settings.status != "shutdown" &&
         length(positions) < settings.chunks do
      :rebuy
    else
      :skip
    end
  end

  def generate_decision(
        %TradeEvent{},
        _position,
        _positions,
        _settings
      ) do
    :skip
  end

  defp execute_decision(
         {:place_buy_order, price, quantity},
         %Position{
           id: id,
           symbol: symbol
         } = position,
         _settings
       ) do
    Logger.info(
      "Position (#{symbol}/#{id}): " <>
        "Placing a BUY order @ #{price}, quantity: #{quantity}"
    )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_buy(symbol, quantity, price, "GTC")

    :ok = broadcast_order(order)

    {:ok, %{position | buy_order: order}}
  end

  defp execute_decision(
         {:place_sell_order, sell_price},
         %Position{
           id: id,
           symbol: symbol,
           buy_order: %Binance.OrderResponse{
             orig_qty: quantity
           }
         } = position,
         _settings
       ) do
    Logger.info(
      "Position (#{symbol}/#{id}): " <>
        "Placing a SELL order @ #{sell_price}, quantity: #{quantity}"
    )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_sell(symbol, quantity, sell_price, "GTC")

    :ok = broadcast_order(order)

    {:ok, %{position | sell_order: order}}
  end

  defp execute_decision(
         :fetch_buy_order,
         %Position{
           id: id,
           symbol: symbol,
           buy_order: %Binance.OrderResponse{
             order_id: order_id,
             transact_time: timestamp
           }
         } = position,
         _settings
       ) do
    Logger.info("Position (#{symbol}/#{id}): The BUY order is now filled")

    {:ok, %Binance.Order{} = current_buy_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    buy_order_response = convert_order_to_order_response(current_buy_order)
    :ok = broadcast_order(buy_order_response)

    {:ok, %{position | buy_order: buy_order_response}}
  end

  defp execute_decision(
         :finished,
         %Position{
           id: id,
           symbol: symbol
         },
         settings
       ) do
    new_position = generate_fresh_position(settings)
    Logger.info("Position (#{symbol}/#{id}): Trade cycle finished")
    {:ok, new_position}
  end

  defp execute_decision(
         :fetch_sell_order,
         %Position{
           id: id,
           symbol: symbol,
           sell_order: %Binance.OrderResponse{
             order_id: order_id,
             transact_time: timestamp
           }
         } = position,
         _settings
       ) do
    Logger.info("Position (#{symbol}/#{id}): The SELL order is now filled")

    {:ok, %Binance.Order{} = current_sell_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    sell_order_response = convert_order_to_order_response(current_sell_order)
    :ok = broadcast_order(sell_order_response)

    {:ok, %{position | sell_order: sell_order_response}}
  end

  defp execute_decision(
         :rebuy,
         %Position{
           id: id,
           symbol: symbol
         },
         settings
       ) do
    new_position = generate_fresh_position(settings)
    Logger.info("Position (#{symbol}/#{id}): Rebuy triggered. Starting a new position")
    {:ok, new_position}
  end

  defp execute_decision(
         :skip,
         position,
         _settings
       ) do
    {:ok, position}
  end

  def parse_results([]) do
    :exit
  end

  def parse_results([_ | _] = results) do
    results
    |> Enum.map(fn {:ok, new_position} -> new_position end)
    |> then(&{:ok, &1})
  end

  def calculate_sell_price(buy_price, profit_target, tick_size) do
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

  def calculate_buy_price(current_price, buy_down_interval, tick_size) do
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

  def calculate_quantity(budget, price, step_size) do
    budget
    |> D.div(D.from_float(price))
    |> D.div_int(step_size)
    |> D.mult(step_size)
    |> D.to_string(:normal)
  end

  def trigger_rebuy?(buy_price, current_price, rebuy_interval) do
    buy_price = Decimal.from_float(buy_price)
    current_price = Decimal.from_float(current_price)

    rebuy_price =
      D.sub(
        buy_price,
        D.mult(buy_price, rebuy_interval)
      )

    D.lt?(current_price, rebuy_price)
  end

  defp convert_order_to_order_response(%Binance.Order{} = order) do
    response = struct(Binance.OrderResponse, Map.from_struct(order))
    %{response | transact_time: order.time}
  end

  defp broadcast_order(%Binance.OrderResponse{} = response) do
    order =
      response
      |> convert_to_order()

    Phoenix.PubSub.broadcast(
      Hedgehog.PubSub,
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

  def fetch_symbol_settings(symbol) do
    {:ok, exchange_info} = @binance_client.get_exchange_info()
    db_settings = Repo.get_by!(Settings, symbol: symbol)

    merge_filters_into_settings(exchange_info, db_settings, symbol)
  end

  def merge_filters_into_settings(exchange_info, db_settings, symbol) do
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

    Map.merge(
      %{
        tick_size: tick_size,
        step_size: step_size
      },
      db_settings |> Map.from_struct()
    )
  end

  def generate_fresh_position(settings, id \\ :os.system_time(:millisecond)) do
    %{
      struct(Position, settings)
      | id: id,
        budget: D.div(settings.budget, settings.chunks),
        rebuy_notified: false
    }
  end

  def update_status(symbol, status)
      when is_binary(symbol) and is_binary(status) do
    Repo.get_by(Settings, symbol: symbol)
    |> Ecto.Changeset.change(%{status: status})
    |> Repo.update()
  end
end
