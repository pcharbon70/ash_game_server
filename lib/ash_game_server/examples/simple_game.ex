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
      %{
        name: :position,
        type: :struct,
        attributes: [
          %{name: :x, type: :float, default: 0.0},
          %{name: :y, type: :float, default: 0.0},
          %{name: :z, type: :float, default: 0.0}
        ]
      },
      %{
        name: :velocity,
        type: :struct,
        attributes: [
          %{name: :dx, type: :float, default: 0.0},
          %{name: :dy, type: :float, default: 0.0},
          %{name: :dz, type: :float, default: 0.0}
        ]
      },
      %{
        name: :health,
        type: :struct,
        attributes: [
          %{name: :current, type: :integer, default: 100},
          %{name: :max, type: :integer, default: 100}
        ]
      },
      %{
        name: :inventory,
        type: :struct,
        attributes: [
          %{name: :items, type: :list, default: []},
          %{name: :capacity, type: :integer, default: 10}
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