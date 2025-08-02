defmodule AshGameServer.Players do
  @moduledoc """
  Players domain managing player-related entities.
  
  This domain handles:
  - Player profiles
  - Player statistics
  - Player inventory
  - Player sessions
  """
  use Ash.Domain

  resources do
    resource AshGameServer.Players.Player
    # Additional player resources will be added here
  end
end