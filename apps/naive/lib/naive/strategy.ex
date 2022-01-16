defmodule Naive.Strategy do
  alias Decimal, as: D
  alias Core.Struct.TradeEvent
  alias Naive.Trader.State

  def generate_decision(
        %TradeEvent{price: price},
        %State{
          budget: budget,
          buy_order: nil,
          buy_down_interval: buy_down_interval,
          tick_size: tick_size,
          step_size: step_size
        }
      ) do
    price = calculate_buy_price(price, buy_down_interval, tick_size)

    quantity = calculate_quantity(budget, price, step_size)

    {:place_buy_order, price, quantity}
  end

  def generate_decision(
        %TradeEvent{
          buyer_order_id: order_id
        },
        %State{
          buy_order: %Binance.OrderResponse{
            order_id: order_id,
            status: "FILLED"
          },
          sell_order: %Binance.OrderResponse{}
        }
      ) do
    :skip
  end

  def generate_decision(
        %TradeEvent{},
        %State{
          buy_order: %Binance.OrderResponse{
            status: "FILLED",
            price: buy_price
          },
          sell_order: nil,
          profit_interval: profit_interval,
          tick_size: tick_size
        }
      ) do
    sell_price = calculate_sell_price(buy_price, profit_interval, tick_size)
    {:place_sell_order, sell_price}
  end

  def generate_decision(
        %TradeEvent{
          buyer_order_id: order_id
        },
        %State{
          buy_order: %Binance.OrderResponse{
            order_id: order_id
          }
        }
      ) do
    :fetch_buy_order
  end

  def generate_decision(
        %TradeEvent{},
        %State{
          sell_order: %Binance.OrderResponse{
            status: "FILLED"
          }
        }
      ) do
    :exit
  end

  def generate_decision(
        %TradeEvent{
          seller_order_id: order_id
        },
        %State{
          sell_order: %Binance.OrderResponse{
            order_id: order_id
          }
        }
      ) do
    :fetch_sell_order
  end

  def generate_decision(
        %TradeEvent{
          price: current_price
        },
        %State{
          buy_order: %Binance.OrderResponse{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        }
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) do
      :rebuy
    else
      :skip
    end
  end

  def generate_decision(%TradeEvent{}, %State{}) do
    :skip
  end

  def calculate_sell_price(buy_price, profit_interval, tick_size) do
    fee = "1.001"
    original_price = D.mult(buy_price, fee)

    net_target_price =
      D.mult(
        original_price,
        D.add("1.0", profit_interval)
      )

    gross_target_price = D.mult(net_target_price, fee)

    D.to_string(
      D.mult(
        D.div_int(gross_target_price, tick_size),
        tick_size
      ),
      :normal
    )
  end

  def calculate_buy_price(current_price, buy_down_interval, tick_size) do
    # not necessarily legal price
    exact_buy_price =
      D.sub(
        current_price,
        D.mult(current_price, buy_down_interval)
      )

    D.to_string(
      D.mult(
        D.div_int(exact_buy_price, tick_size),
        tick_size
      ),
      :normal
    )
  end

  def calculate_quantity(budget, price, step_size) do
    # not necessarily legal quantity
    exact_target_quantity = D.div(budget, price)

    D.to_string(
      D.mult(
        D.div_int(exact_target_quantity, step_size),
        step_size
      ),
      :normal
    )
  end

  def trigger_rebuy?(buy_price, current_price, rebuy_interval) do
    rebuy_price =
      D.sub(
        buy_price,
        D.mult(buy_price, rebuy_interval)
      )

    D.lt?(current_price, rebuy_price)
  end
end
