defmodule Streamer.Supervisor do
  use Supervisor

  alias Streamer.DynamicStreamerSupervisor

  @registry :binance_streamers

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {Registry, [keys: :unique, name: @registry]},
      {DynamicStreamerSupervisor, []},
      {Task,
       fn ->
         DynamicStreamerSupervisor.autostart_workers()
       end}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
