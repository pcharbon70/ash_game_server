defmodule AshGameServer.ECS.Dsl do
  @moduledoc """
  Base DSL module for ECS (Entity Component System) definitions.
  
  This module provides the foundation for defining components, systems,
  and entities using a declarative DSL powered by Spark.
  """
  
  @doc """
  The ECS DSL module that will be used in game resources.
  
  ## Example
  
      defmodule MyGame.Player do
        use AshGameServer.ECS.Dsl
        
        components do
          component :position, x: 0.0, y: 0.0
        end
      end
  """
  defmacro __using__(opts \\ []) do
    quote location: :keep do
      use Spark.Dsl,
        single_extension_kinds: [:ecs],
        default_extensions: [
          extensions: [AshGameServer.ECS.ComponentExtension]
        ]
      
      @ecs_opts unquote(opts)
      @before_compile AshGameServer.ECS.Dsl
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      def ecs_config do
        %{
          components: AshGameServer.ECS.ComponentExtension.components(__MODULE__),
          systems: AshGameServer.ECS.SystemExtension.systems(__MODULE__),
          entities: AshGameServer.ECS.EntityExtension.entities(__MODULE__)
        }
      end
    end
  end
end