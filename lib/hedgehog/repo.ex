defmodule Hedgehog.Repo do
  use Ecto.Repo,
    otp_app: :hedgehog,
    adapter: Ecto.Adapters.SQLite3
end
