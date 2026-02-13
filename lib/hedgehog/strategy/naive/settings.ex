defmodule Hedgehog.Strategy.Naive.Settings do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "naive_strategy_settings" do
    field(:symbol, :string)
    field(:chunks, :integer)
    field(:budget, :decimal)
    field(:buy_down_interval, :decimal)
    field(:profit_target, :decimal)
    field(:rebuy_interval, :decimal)
    field(:status, Ecto.Enum, values: [:on, :off, :shutdown])

    timestamps()
  end
end
