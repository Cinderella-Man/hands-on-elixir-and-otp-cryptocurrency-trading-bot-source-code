defmodule DataWarehouse.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add(:id, :bigint, primary_key: true)
      add(:symbol, :text)
      add(:price, :text)
      add(:quantity, :text)
      add(:side, :text)
      add(:status, :text)
      add(:timestamp, :bigint)

      timestamps()
    end
  end
end
