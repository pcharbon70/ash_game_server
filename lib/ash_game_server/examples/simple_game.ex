defmodule AshGameServer.Examples.SimpleGame do
  @moduledoc """
  Simple example using the ECS DSL directly.
  """
  
  # Use each extension directly as a module
  require AshGameServer.ECS.ComponentExtension
  require AshGameServer.ECS.SystemExtension
  require AshGameServer.ECS.EntityExtension
  
  # For now, let's create a simple module that demonstrates the DSL concepts
  def example_components do
    [
      %AshGameServer.ECS.Component{
        name: :position,
        attributes: [
          %AshGameServer.ECS.Component.Attribute{
            name: :x,
            type: :float,
            default: 0.0
          },
          %AshGameServer.ECS.Component.Attribute{
            name: :y,
            type: :float,
            default: 0.0
          }
        ]
      },
      %AshGameServer.ECS.Component{
        name: :health,
        attributes: [
          %AshGameServer.ECS.Component.Attribute{
            name: :current,
            type: :integer,
            default: 100
          },
          %AshGameServer.ECS.Component.Attribute{
            name: :max,
            type: :integer,
            default: 100
          }
        ]
      }
    ]
  end
  
  def example_systems do
    [
      %AshGameServer.ECS.System{
        name: :movement,
        priority: 10,
        queries: [
          %AshGameServer.ECS.System.Query{
            components: [:position, :velocity]
          }
        ]
      },
      %AshGameServer.ECS.System{
        name: :combat,
        priority: 20,
        queries: [
          %AshGameServer.ECS.System.Query{
            components: [:health, :combat_stats]
          }
        ]
      }
    ]
  end
  
  def example_archetypes do
    [
      %AshGameServer.ECS.Archetype{
        name: :player,
        components: [
          %AshGameServer.ECS.Entity.ComponentRef{
            name: :position
          },
          %AshGameServer.ECS.Entity.ComponentRef{
            name: :health,
            initial: [max: 150, current: 150]
          }
        ]
      }
    ]
  end
end