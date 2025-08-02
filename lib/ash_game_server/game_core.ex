defmodule AshGameServer.GameCore do
  @moduledoc """
  Core game domain containing fundamental game entities.
  
  This domain manages:
  - Game sessions
  - Game states
  - Core game mechanics
  """
  use Ash.Domain

  resources do
    resource AshGameServer.GameCore.GameSession
    # Additional core resources will be added here
  end
end