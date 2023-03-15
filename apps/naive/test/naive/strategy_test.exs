defmodule Naive.StrategyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Core.Struct.TradeEvent
  alias Naive.Strategy

  import ExUnit.CaptureLog

  @tag :unit
  test "Strategy places a buy order" do
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
      fn "ABC", "50.000", "0.800000", "GTC" -> {:ok, expected_order} end
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
      profit_interval: "0.1",
      rebuy_interval: "0.5",
      tick_size: "0.000001",
      step_size: "0.001",
      status: :on
    }

    {{:ok, new_positions}, log} =
      with_log(fn ->
        Naive.Strategy.execute(
          %TradeEvent{
            price: "1.00000"
          },
          [
            Strategy.generate_fresh_position(settings)
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
    assert Strategy.generate_decision(
             %TradeEvent{
               price: "1.0"
             },
             generate_position(%{
               budget: "10.0",
               buy_down_interval: "0.01"
             }),
             :ignored,
             :ignored
           ) == {:place_buy_order, "0.99000000", "10.00000000"}
  end

  @tag :unit
  test "Generating skip decision as buy and sell already placed(race condition occurred)" do
    assert Strategy.generate_decision(
             %TradeEvent{
               buyer_order_id: 123
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 order_id: 123,
                 status: "FILLED"
               },
               sell_order: %Binance.OrderResponse{}
             }),
             :ignored,
             :ignored
           ) == :skip
  end

  @tag :unit
  test "Generating place sell order decision" do
    assert Strategy.generate_decision(
             %TradeEvent{},
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 status: "FILLED",
                 price: "1.00"
               },
               sell_order: nil,
               profit_interval: "0.01",
               tick_size: "0.0001"
             }),
             :ignored,
             :ignored
           ) == {:place_sell_order, "1.0120"}
  end

  @tag :unit
  test "Generating fetch buy order decision" do
    assert Strategy.generate_decision(
             %TradeEvent{
               buyer_order_id: 1234
             },
             generate_position(%{
               buy_order: %Binance.OrderResponse{
                 order_id: 1234
               }
             }),
             :ignored,
             :ignored
           ) == :fetch_buy_order
  end

  defp generate_position(data) do
    %{
      id: 1_678_920_020_426,
      symbol: "XRPUSDT",
      profit_interval: "0.005",
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
    |> then(&struct(Strategy.Position, &1))
  end
end
