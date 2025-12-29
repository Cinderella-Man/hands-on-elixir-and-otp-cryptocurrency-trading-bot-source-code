defmodule Hedgehog.Strategy.Naive.FormulaTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hedgehog.Exchange.BinanceMock
  alias Hedgehog.Exchange.TradeEvent
  alias Hedgehog.Strategy.Naive.Formula

  import ExUnit.CaptureLog

  @tag :unit
  test "Formula places a buy order" do
    expected_order = %Binance.OrderResponse{
      client_order_id: "1",
      executed_qty: "0.000",
      order_id: "x1",
      orig_qty: "50.000",
      price: "0.800000",
      side: "BUY",
      status: "NEW",
      symbol: "ABC"
    }

    BinanceMock
    |> stub(
      :order_limit_buy,
      fn "ABC", "50.000", 0.8, "GTC" -> {:ok, expected_order} end
    )

    Phoenix.PubSub
    |> stub(
      :broadcast,
      fn _pubsub, _topic, _message -> :ok end
    )

    settings = %{
      symbol: "ABC",
      chunks: "5",
      budget: "200",
      buy_down_interval: "0.2",
      profit_target: "0.1",
      rebuy_interval: "0.5",
      tick_size: "0.000001",
      step_size: "0.001",
      status: :on
    }

    {{:ok, new_positions}, log} =
      with_log(fn ->
        Formula.execute(
          %TradeEvent{
            price: 1.00
          },
          [
            Formula.generate_fresh_position(settings)
          ],
          settings
        )
      end)

    assert log =~ "0.8"

    assert length(new_positions) == 1

    %{buy_order: buy_order} = List.first(new_positions)
    assert buy_order == expected_order
  end

  @tag :unit
  test "Generating place buy order decision" do
    assert Formula.generate_decision(
             %TradeEvent{
               price: 1.0
             },
             generate_position(%{
               budget: "10.0",
               buy_down_interval: "0.01"
             }),
             :ignored,
             :ignored
           ) == {:place_buy_order, 0.99000000, "10.00000000"}
  end

  @tag :unit
  test "Generating place sell order decision" do
    assert Formula.generate_decision(
             %TradeEvent{},
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 status: "FILLED",
                 price: 1.00
               },
               sell_order: nil,
               profit_target: "0.01",
               tick_size: "0.0001"
             }),
             :ignored,
             :ignored
           ) == {:place_sell_order, 1.0120}
  end

  @tag :unit
  test "Generating fetch buy order decision" do
    assert Formula.generate_decision(
             %TradeEvent{
               price: 1.01
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 price: 1.02
               }
             }),
             :ignored,
             :ignored
           ) == :fetch_buy_order
  end

  @tag :unit
  test "Generating finish position decision" do
    assert Formula.generate_decision(
             %TradeEvent{},
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 status: "FILLED"
               },
               sell_order: %Binance.OrderResponse{
                 status: "FILLED"
               }
             }),
             :ignored,
             %{status: "on"}
           ) == :finished
  end

  @tag :unit
  test "Generating exit position decision" do
    assert Formula.generate_decision(
             %TradeEvent{},
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 status: "FILLED"
               },
               sell_order: %Binance.OrderResponse{
                 status: "FILLED"
               }
             }),
             :ignored,
             %{status: "shutdown"}
           ) == :exit
  end

  @tag :unit
  test "Generating fetch sell order decision" do
    assert Formula.generate_decision(
             %TradeEvent{
               price: 1.02
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{},
               sell_order: %Binance.OrderResponse{
                 price: 1.01
               }
             }),
             :ignored,
             :ignored
           ) == :fetch_sell_order
  end

  @tag :unit
  test "Generating rebuy decision" do
    assert Formula.generate_decision(
             %TradeEvent{
               price: 0.89
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 price: 1.00
               },
               sell_order: %Binance.OrderResponse{
                 price: 1.1
               },
               rebuy_interval: "0.1",
               rebuy_notified: false
             }),
             [:position],
             %{status: "on", chunks: 2}
           ) == :rebuy
  end

  @tag :unit
  test "Generating skip(rebuy) decision because rebuy is already notified" do
    assert Formula.generate_decision(
             %TradeEvent{
               price: 0.89
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 price: 1.00
               },
               sell_order: %Binance.OrderResponse{
                 price: 1.1
               },
               rebuy_interval: 0.1,
               rebuy_notified: true
             }),
             [:position],
             %{status: "on", chunks: 2}
           ) == :skip
  end

  @tag :unit
  test "Generating skip decision" do
    assert Formula.generate_decision(
             %TradeEvent{
               price: 0.9
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 price: 1.00
               },
               sell_order: %Binance.OrderResponse{
                 price: 1.1
               },
               rebuy_interval: "0.1",
               rebuy_notified: false
             }),
             [:position],
             %{status: "on", chunks: 1}
           ) == :skip
  end

  defp generate_position(data) do
    %{
      id: 1_678_920_020_426,
      symbol: "XRPUSDT",
      profit_target: "0.005",
      rebuy_interval: "0.01",
      rebuy_notified: false,
      budget: "10.0",
      buy_order: nil,
      sell_order: nil,
      buy_down_interval: "0.01",
      tick_size: "0.00010000",
      step_size: "1.00000000"
    }
    |> Map.merge(data)
    |> then(&struct(Formula.Position, &1))
  end
end
