defmodule AshGameServerTest do
  use ExUnit.Case
  doctest AshGameServer

  test "greets the world" do
    assert AshGameServer.hello() == :world
  end
end
