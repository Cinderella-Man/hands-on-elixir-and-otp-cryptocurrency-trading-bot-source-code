defmodule DataWarehouse.Schema.Order do
  use Ecto.Schema
  @primary_key {:order_id, :integer, autogenerate: false}
  schema "orders" do
    field(:client_order_id, :string)
    field(:symbol, :string)
    field(:price, :decimal)
    field(:original_quantity, :decimal)
    field(:executed_quantity, :decimal)
    field(:cummulative_quote_quantity, :decimal)
    field(:status, :string)
    field(:time_in_force, :string)
    field(:type, :string)
    field(:side, :string)
    field(:stop_price, :decimal)
    field(:iceberg_quantity, :decimal)
    field(:time, :integer)
    field(:update_time, :integer)
    timestamps()
  end
end
