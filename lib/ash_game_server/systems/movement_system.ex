defmodule AshGameServer.Systems.MovementSystem do
  @moduledoc """
  Movement System for handling entity position updates and physics integration.
  
  Processes entities with Position, Velocity, and Physics components to update
  their positions, handle collisions, and apply movement constraints.
  """
  
  use AshGameServer.Systems.SystemBehaviour
  
  alias AshGameServer.Components.Transform.{Position, Velocity}
  alias AshGameServer.Components.Physics.{RigidBody, Collider}
  
  @type movement_state :: %{
    delta_time: float(),
    world_bounds: %{min_x: float(), max_x: float(), min_y: float(), max_y: float()},
    collision_enabled: boolean()
  }
  
  @impl true
  def init(_opts) do
    {:ok, %{
      delta_time: 0.0,
      world_bounds: %{min_x: -1000.0, max_x: 1000.0, min_y: -1000.0, max_y: 1000.0},
      collision_enabled: true
    }}
  end
  
  @impl true
  def priority, do: 100
  
  @impl true
  def required_components, do: [Position, Velocity]
  
  @impl true
  def execute(entities, state) do
    # Process all entities with position and velocity
    Enum.each(entities, fn {entity_id, components} ->
      process_entity(entity_id, components, state)
    end)
    
    {:ok, state}
  end
  
  @impl true
  def process_entity(entity_id, components, state) do
    with {:ok, position} <- get_component(entity_id, Position),
         {:ok, velocity} <- get_component(entity_id, Velocity) do
      
      # Calculate new position
      new_position = apply_velocity(position, velocity, state.delta_time)
      
      # Apply world bounds
      bounded_position = apply_world_bounds(new_position, state.world_bounds)
      
      # Check for collisions if enabled
      final_position = if state.collision_enabled do
        check_collisions(entity_id, bounded_position, state)
      else
        bounded_position
      end
      
      # Update position component
      update_component(entity_id, Position, final_position)
      
      # Apply physics constraints if entity has rigid body
      case get_component(entity_id, RigidBody) do
        {:ok, rigid_body} ->
          apply_physics_constraints(entity_id, final_position, velocity, rigid_body)
        _ ->
          :ok
      end
    else
      _ -> :skip
    end
    
    {:ok, components}
  end
  
  # Private functions
  
  defp apply_velocity(%Position{} = pos, %Velocity{} = vel, delta_time) do
    %Position{pos |
      x: pos.x + vel.linear_x * delta_time,
      y: pos.y + vel.linear_y * delta_time,
      z: pos.z + vel.linear_z * delta_time
    }
  end
  
  defp apply_world_bounds(%Position{} = pos, bounds) do
    %Position{pos |
      x: clamp(pos.x, bounds.min_x, bounds.max_x),
      y: clamp(pos.y, bounds.min_y, bounds.max_y)
    }
  end
  
  defp clamp(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
  
  defp check_collisions(_entity_id, position, _state) do
    # In a real implementation, this would query other entities with colliders
    # For now, just return the position unchanged
    position
  end
  
  defp collides?(%Position{} = pos1, %Collider{} = col1, %Position{} = pos2, %Collider{} = col2) do
    dx = pos1.x - pos2.x
    dy = pos1.y - pos2.y
    distance = :math.sqrt(dx * dx + dy * dy)
    
    distance < (col1.radius + col2.radius)
  end
  
  defp resolve_collision(%Position{} = pos1, %Collider{} = col1, %Position{} = pos2, %Collider{} = col2) do
    # Simple push-out resolution
    dx = pos1.x - pos2.x
    dy = pos1.y - pos2.y
    distance = :math.sqrt(dx * dx + dy * dy)
    
    if distance > 0 do
      # Normalize and push out
      overlap = (col1.radius + col2.radius) - distance
      push_x = (dx / distance) * overlap * 0.5
      push_y = (dy / distance) * overlap * 0.5
      
      %Position{pos1 |
        x: pos1.x + push_x,
        y: pos1.y + push_y
      }
    else
      pos1
    end
  end
  
  defp apply_physics_constraints(entity_id, _position, velocity, rigid_body) do
    # Apply drag/friction
    dampened_velocity = %Velocity{velocity |
      linear_x: velocity.linear_x * (1.0 - rigid_body.drag),
      linear_y: velocity.linear_y * (1.0 - rigid_body.drag),
      linear_z: velocity.linear_z * (1.0 - rigid_body.drag)
    }
    
    # Apply gravity if enabled
    gravity_velocity = if rigid_body.use_gravity do
      %Velocity{dampened_velocity |
        linear_y: dampened_velocity.linear_y - 9.81 * 0.016  # Assuming 60fps
      }
    else
      dampened_velocity
    end
    
    update_component(entity_id, Velocity, gravity_velocity)
  end
  
  # Component access helpers
  defp get_component(entity_id, component_type) do
    case AshGameServer.Storage.ComponentStorage.get(component_type, entity_id) do
      {:ok, component} -> {:ok, component}
      _ -> {:error, :not_found}
    end
  end
  
  defp update_component(entity_id, component_type, component) do
    AshGameServer.Storage.ComponentStorage.put(component_type, entity_id, component)
  end
  
  # Public API for external control
  
  @doc """
  Set the delta time for movement calculations.
  """
  def set_delta_time(state, delta_time) when is_number(delta_time) and delta_time > 0 do
    %{state | delta_time: delta_time}
  end
  
  @doc """
  Update world boundaries for movement constraints.
  """
  def set_world_bounds(state, min_x, max_x, min_y, max_y) do
    %{state | world_bounds: %{min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y}}
  end
  
  @doc """
  Enable or disable collision detection.
  """
  def set_collision_enabled(state, enabled) when is_boolean(enabled) do
    %{state | collision_enabled: enabled}
  end
end