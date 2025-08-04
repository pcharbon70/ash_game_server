defmodule AshGameServer.Jido do
  @moduledoc """
  Jido framework integration for the game server.

  This module provides the foundation for autonomous agent systems
  within the game server, including supervision, registry, and signal routing.
  """
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Agent registry for distributed agent discovery
      {AshGameServer.Jido.AgentRegistry, []},
      # Signal router for agent communication
      {AshGameServer.Jido.SignalRouter, []},
      # Dynamic supervisor for game agents
      {DynamicSupervisor, name: AshGameServer.Jido.AgentSupervisor, strategy: :one_for_one},
      # Agent monitor for health checking
      {AshGameServer.Jido.AgentMonitor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Start a new agent under supervision.
  """
  def start_agent(agent_module, opts \\ []) do
    child_spec = {agent_module, opts}
    DynamicSupervisor.start_child(AshGameServer.Jido.AgentSupervisor, child_spec)
  end

  @doc """
  Stop an agent gracefully.
  """
  def stop_agent(agent_pid) when is_pid(agent_pid) do
    DynamicSupervisor.terminate_child(AshGameServer.Jido.AgentSupervisor, agent_pid)
  end

  @doc """
  List all running agents.
  """
  def list_agents do
    DynamicSupervisor.which_children(AshGameServer.Jido.AgentSupervisor)
  end
end
