defmodule Hedgehog.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HedgehogWeb.Telemetry,
      Hedgehog.Repo,
      {DNSCluster, query: Application.get_env(:hedgehog, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hedgehog.PubSub},
      # Start a worker by calling: Hedgehog.Worker.start_link(arg)
      # {Hedgehog.Worker, arg},
      # Start to serve requests, typically the last entry
      HedgehogWeb.Endpoint,
      Hedgehog.Exchange.BinanceMock,
      Hedgehog.Streamer.Binance.Supervisor,
      Hedgehog.Strategy.Naive.Supervisor,
      Hedgehog.Data.Collector.CollectorSupervisor,
      {DynamicSupervisor,
       strategy: :one_for_one, name: Hedgehog.Data.Aggregator.DynamicWorkerSupervisor}
    ] ++ litestream_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hedgehog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HedgehogWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp litestream_children do
    config = Application.get_env(:hedgehog, Hedgehog.Litestream, [])

    if Keyword.get(config, :enabled, false) do
      strategy =
        struct(Litestream.Strategy.ObjectStorage, config[:strategy])

      opts =
        config
        |> Keyword.drop([:enabled, :strategy])

      [{Litestream, Keyword.put(opts, :strategy, strategy)}]
    else
      []
    end
  end
end
