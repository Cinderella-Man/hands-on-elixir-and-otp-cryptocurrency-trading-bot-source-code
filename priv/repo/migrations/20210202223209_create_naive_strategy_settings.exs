defmodule Hedgehog.Repo.Migrations.CreateNaiveStrategySettings do
  use Ecto.Migration

  def change do
    create table(:naive_strategy_settings, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:symbol, :text, null: false)
      add(:chunks, :integer, null: false)
      add(:budget, :decimal, null: false)
      add(:buy_down_interval, :decimal, null: false)
      add(:profit_target, :decimal, null: false)
      add(:rebuy_interval, :decimal, null: false)
      add(:status, :string, default: "off", null: false)

      timestamps()
    end

    create(unique_index(:naive_strategy_settings, [:symbol]))
  end
end
