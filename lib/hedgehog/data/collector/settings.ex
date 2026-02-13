defmodule Hedgehog.Data.Collector.Settings do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "collector_settings" do
    field(:topic, :string)
    field(:status, Ecto.Enum, values: [:on, :off])

    timestamps()
  end
end
