defmodule Hedgehog.Exchange.TradeEvent do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event_type: String.t() | nil,
          event_time: integer() | nil,
          symbol: String.t() | nil,
          trade_id: integer() | nil,
          price: Decimal.t() | nil,
          quantity: Decimal.t() | nil,
          trade_time: integer() | nil,
          buyer_market_maker: boolean() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "trade_events" do
    field(:event_type, :string)
    field(:event_time, :integer)
    field(:symbol, :string)
    field(:trade_id, :integer)
    field(:price, :decimal)
    field(:quantity, :decimal)
    field(:trade_time, :integer)
    field(:buyer_market_maker, :boolean)

    timestamps()
  end
end
