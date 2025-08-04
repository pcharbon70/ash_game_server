defmodule AshGameServer.PubSubHelper do
  @moduledoc """
  Helper module for Ash.Notifier.PubSub integration.

  This module provides the broadcast function required by Ash.Notifier.PubSub
  to publish events via Phoenix.PubSub.
  """

  @doc """
  Broadcast a notification to Phoenix.PubSub.

  This function is called by Ash.Notifier.PubSub when resources publish events.
  """
  def broadcast(topic, event, notification) do
    Phoenix.PubSub.broadcast(
      AshGameServer.PubSub,
      topic,
      {event, notification}
    )
  end
end
