defmodule Hedgehog.Repo.Migrations.CreateCollectorSettings do
  use Ecto.Migration

  alias Hedgehog.Data.Collector.SettingsStatusEnum

  def change do
    SettingsStatusEnum.create_type()

    create table(:collector_settings, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:topic, :text, null: false)
      add(:status, SettingsStatusEnum.type(), default: "off", null: false)

      timestamps()
    end

    create(unique_index(:collector_settings, [:topic]))
  end
end
