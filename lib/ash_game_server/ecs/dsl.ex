defmodule AshGameServer.ECS.DSL do
  @moduledoc """
  Main DSL module that combines all ECS extensions.
  Provides a unified interface for defining components, systems, and entities.
  """
  
  defmacro __using__(_opts) do
    quote do
      use Spark.Dsl,
        single_extension_kinds: [:ecs],
        extensions: [
          AshGameServer.ECS.ComponentExtension,
          AshGameServer.ECS.SystemExtension,
          AshGameServer.ECS.EntityExtension
        ]
    end
  end
end