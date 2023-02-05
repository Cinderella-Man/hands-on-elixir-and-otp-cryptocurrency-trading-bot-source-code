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
      fn("ABC", "50.000", "0.800000", "GTC") -> {:ok, expected_order} end
    )

    Phoenix.PubSub
    |> stub(
      :broadcast,
      fn(_pubsub, _topic, _message) -> :ok end
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

    {{:ok, new_positions}, log} = with_log(fn ->
      Naive.Strategy.execute(
        %TradeEvent{
          price: "1.00000"
        },
        [
          Strategy.generate_fresh_position(settings)
        ],
        settings
      ) end)

    assert (length new_positions) == 1
    assert log =~ "0.8"

    %{buy_order: buy_order} = List.first(new_positions)

    assert buy_order == expected_order
  end
end
