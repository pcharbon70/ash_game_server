defmodule AshGameServer.Application do
  @moduledoc """
  The AshGameServer Application module.
  
  This module starts the supervision tree for the game server,
  including all necessary processes for ECS, agents, and web interface.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      AshGameServer.Repo,
      # Start Telemetry supervisor
      AshGameServer.Telemetry,
      # Start Phoenix PubSub
      {Phoenix.PubSub, name: AshGameServer.PubSub}
      # Game-specific supervisors will be added here
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshGameServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end