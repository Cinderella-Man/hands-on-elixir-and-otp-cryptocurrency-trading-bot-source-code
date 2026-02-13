defmodule Hedgehog.Repo.Migrations.CreateCollectorSettings do
  use Ecto.Migration

  def change do
    create table(:collector_settings, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:topic, :text, null: false)
      add(:status, :string, default: "off", null: false)

      timestamps()
    end

    create(unique_index(:collector_settings, [:topic]))
  end
end
