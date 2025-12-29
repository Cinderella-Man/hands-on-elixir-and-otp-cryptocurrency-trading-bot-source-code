defmodule Hedgehog.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add(:order_id, :bigint, primary_key: true)
      add(:client_order_id, :text)
      add(:symbol, :text)
      add(:price, :decimal)
      add(:original_quantity, :decimal)
      add(:executed_quantity, :decimal)
      add(:cummulative_quote_quantity, :decimal)
      add(:status, :text)
      add(:time_in_force, :text)
      add(:type, :text)
      add(:side, :text)
      add(:stop_price, :decimal)
      add(:iceberg_quantity, :decimal)
      add(:time, :bigint)
      add(:update_time, :bigint)

      timestamps()
    end
  end
end
