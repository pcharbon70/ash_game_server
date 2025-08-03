defmodule AshGameServer.Agents.NPCAgent do
  @moduledoc """
  Stub implementation for NPC agent.
  Will be fully implemented in later phases.
  """
  
  def get_behavior(_pid), do: :patrol
  def set_behavior(_pid, _behavior), do: :ok
end