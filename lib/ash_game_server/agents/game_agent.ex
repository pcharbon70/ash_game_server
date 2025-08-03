defmodule AshGameServer.Agents.GameAgent do
  @moduledoc """
  Stub implementation for game agent.
  Will be fully implemented in later phases.
  """

  def get_state(_pid), do: %{entity_id: 1}
  def move_to(_pid, _position), do: :ok
  def update_score(_pid, _amount), do: :ok
  def get_health(_pid), do: %{current: 100, max: 100}
end