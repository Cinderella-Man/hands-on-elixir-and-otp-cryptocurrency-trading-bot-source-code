defmodule DataWarehouse.Schema.Order do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}

  schema "orders" do
    field(:symbol, :string)
    field(:price, :string)
    field(:quantity, :string)
    field(:side, :string)
    field(:status, :string)
    field(:timestamp, :integer)

    timestamps()
  end
end
