defmodule AshGameServer.Jido.AgentSupervisor do
  @moduledoc """
  Stub implementation for Jido agent supervisor.
  Will be fully implemented in later phases.
  """
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def start_agent(_supervisor, _module, _args) do
    {:ok, spawn(fn -> Process.sleep(:infinity) end)}
  end
  
  def get_agent(_supervisor, _entity_id) do
    {:ok, spawn(fn -> Process.sleep(:infinity) end)}
  end
  
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
end