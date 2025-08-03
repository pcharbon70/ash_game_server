defmodule AshGameServer.Agents.PlayerAgent do
  @moduledoc """
  Stub implementation for player agent.
  Will be fully implemented in later phases.
  """

  def send_message(_from, _to, _message), do: :ok
  def get_messages(_pid), do: [{:chat, "Hello!", from: 1}]
end