defmodule AshGameServer.Systems.AISystem do
  @moduledoc """
  AI System for managing artificial intelligence behaviors and decision making.
  
  Processes entities with AI components to handle decision trees, pathfinding,
  behavior trees, perception, and group coordination.
  """
  
  use AshGameServer.Systems.SystemBehaviour
  
  alias AshGameServer.Components.AI.{AIController, Perception}
  alias AshGameServer.Components.Transform.{Position, Velocity}
  alias AshGameServer.Components.Gameplay.{Health, Combat}
  
  @type ai_state :: %{
    global_ai_enabled: boolean(),
    decision_frequency: float(),
    pathfinding_enabled: boolean(),
    group_coordination: boolean(),
    behavior_stats: %{atom() => integer()}
  }
  
  @type pathfinding_node :: %{
    x: float(),
    y: float(),
    g_cost: float(),
    h_cost: float(),
    f_cost: float(),
    parent: pathfinding_node() | nil
  }
  
  @impl true
  def init(_opts) do
    {:ok, %{
      global_ai_enabled: true,
      decision_frequency: 200.0,  # milliseconds
      pathfinding_enabled: true,
      group_coordination: true,
      behavior_stats: %{}
    }}
  end
  
  @impl true
  def priority, do: 80
  
  @impl true
  def required_components, do: [AIController, Position]
  
  @impl true
  def execute(entities, state) do
    if state.global_ai_enabled do
      # Process each AI entity
      Enum.each(entities, fn {entity_id, components} ->
        process_entity(entity_id, components, state)
      end)
      
      # Update behavior trees
      process_behavior_trees(state)
      
      # Handle perception updates
      process_perception(state)
      
      # Coordinate group behaviors
      if state.group_coordination do
        process_group_coordination(state)
      end
    end
    
    {:ok, state}
  end
  
  @impl true
  def process_entity(entity_id, components, state) do
    with {:ok, ai_controller} <- get_component(entity_id, AIController),
         true <- ai_controller.enabled do
      
      # Update AI timers
      updated_ai = AIController.update_timers(ai_controller, state.decision_frequency)
      
      # Make decisions if needed
      final_ai = if AIController.needs_decision?(updated_ai) do
        make_ai_decision(entity_id, updated_ai, state)
        |> AIController.reset_decision_timer()
      else
        updated_ai
      end
      
      # Update AI component
      update_component(entity_id, AIController, final_ai)
    else
      _ -> :skip
    end
    
    {:ok, components}
  end
  
  # Private functions
  
  defp process_ai_decisions(_state) do
    # In a real implementation, this would query AI entities
    # For now, just return :ok
    :ok
  end
  
  defp process_behavior_trees(_state) do
    # In a real implementation, this would query entities with Behavior components
    # For now, just return :ok
    :ok
  end
  
  defp process_perception(_state) do
    # In a real implementation, this would query entities with Perception components
    # For now, just return :ok
    :ok
  end
  
  defp process_group_coordination(_state) do
    # In a real implementation, this would query AI entities and coordinate groups
    # For now, just return :ok
    :ok
  end
  
  defp make_ai_decision(entity_id, ai_controller, state) do
    # Get current context
    context = build_decision_context(entity_id, state)
    
    # Make decision based on current state and behavior type
    new_state = case ai_controller.state do
      :idle -> decide_from_idle(entity_id, ai_controller, context)
      :patrol -> decide_from_patrol(entity_id, ai_controller, context)
      :chase -> decide_from_chase(entity_id, ai_controller, context)
      :attack -> decide_from_attack(entity_id, ai_controller, context)
      :flee -> decide_from_flee(entity_id, ai_controller, context)
      _ -> ai_controller.state
    end
    
    # Update AI state if changed
    if new_state != ai_controller.state do
      AIController.change_state(ai_controller, new_state)
    else
      ai_controller
    end
  end
  
  defp build_decision_context(entity_id, _state) do
    %{
      position: get_component(entity_id, Position) |> elem(1),
      health: get_component(entity_id, Health),
      combat: get_component(entity_id, Combat),
      perception: get_component(entity_id, Perception),
      nearby_entities: find_nearby_entities(entity_id, 50.0)
    }
  end
  
  defp decide_from_idle(entity_id, ai_controller, context) do
    cond do
      # Check for threats
      has_threats?(context) ->
        case ai_controller.behavior_type do
          :aggressive -> :chase
          :defensive -> :flee
          _ -> :idle
        end
      
      # Check for patrol route
      length(ai_controller.patrol_points) > 0 ->
        :patrol
      
      # Random wandering for some behavior types
      ai_controller.behavior_type == :neutral and :rand.uniform() < 0.1 ->
        move_randomly(entity_id)
        :idle
      
      true ->
        :idle
    end
  end
  
  defp decide_from_patrol(entity_id, ai_controller, context) do
    if has_threats?(context) do
      case ai_controller.behavior_type do
        :aggressive -> :chase
        :defensive -> :flee
        _ -> continue_patrol(entity_id, ai_controller)
      end
    else
      continue_patrol(entity_id, ai_controller)
      :patrol
    end
  end
  
  defp decide_from_chase(entity_id, ai_controller, context) do
    cond do
      # Lost target or no threats
      not has_threats?(context) ->
        case ai_controller.behavior_type do
          :aggressive -> :patrol  # Return to patrol
          _ -> :idle
        end
      
      # Close enough to attack
      in_attack_range?(entity_id, ai_controller.target_entity) ->
        :attack
      
      # Continue chasing
      true ->
        move_towards_target(entity_id, ai_controller.target_entity)
        :chase
    end
  end
  
  defp decide_from_attack(entity_id, ai_controller, context) do
    cond do
      # Target dead or gone
      not target_alive?(ai_controller.target_entity) ->
        :idle
      
      # Target too far
      not in_attack_range?(entity_id, ai_controller.target_entity) ->
        :chase
      
      # Low health, might flee
      low_health?(context) and ai_controller.behavior_type == :defensive ->
        :flee
      
      # Continue attacking
      true ->
        execute_attack(entity_id, ai_controller.target_entity)
        :attack
    end
  end
  
  defp decide_from_flee(entity_id, ai_controller, context) do
    cond do
      # Safe distance reached
      not has_threats?(context) ->
        :idle
      
      # Health recovered enough
      not low_health?(context) ->
        case ai_controller.behavior_type do
          :aggressive -> :chase
          _ -> :idle
        end
      
      # Continue fleeing
      true ->
        flee_from_threats(entity_id, context)
        :flee
    end
  end
  
  defp has_threats?(%{perception: {:ok, perception}}) do
    Perception.has_threats?(perception)
  end
  defp has_threats?(_), do: false
  
  defp low_health?(%{health: {:ok, health}}) do
    health.current / health.maximum < 0.3
  end
  defp low_health?(_), do: false
  
  defp in_attack_range?(entity_id, target_id) when is_binary(target_id) do
    with {:ok, pos1} <- get_component(entity_id, Position),
         {:ok, pos2} <- get_component(target_id, Position),
         {:ok, combat} <- get_component(entity_id, Combat) do
      
      distance = Position.distance(pos1, pos2)
      attack_range = get_attack_range(combat)
      
      distance <= attack_range
    else
      _ -> false
    end
  end
  defp in_attack_range?(_, _), do: false
  
  defp target_alive?(target_id) when is_binary(target_id) do
    case get_component(target_id, Health) do
      {:ok, health} -> health.current > 0
      _ -> false
    end
  end
  defp target_alive?(_), do: false
  
  defp continue_patrol(entity_id, ai_controller) do
    case AIController.next_patrol_point(ai_controller) do
      {nil, _} -> :ok
      {point, updated_ai} ->
        move_towards_point(entity_id, point)
        update_component(entity_id, AIController, updated_ai)
    end
  end
  
  defp move_towards_target(entity_id, target_id) when is_binary(target_id) do
    with {:ok, pos1} <- get_component(entity_id, Position),
         {:ok, pos2} <- get_component(target_id, Position) do
      
      move_towards_position(entity_id, pos1, pos2)
    else
      _ -> :ok
    end
  end
  
  defp move_towards_point(entity_id, point) do
    case get_component(entity_id, Position) do
      {:ok, position} ->
        target_pos = %Position{x: point.x, y: point.y, z: position.z}
        move_towards_position(entity_id, position, target_pos)
      
      _ -> :ok
    end
  end
  
  defp move_towards_position(entity_id, from_pos, to_pos) do
    # Calculate direction
    dx = to_pos.x - from_pos.x
    dy = to_pos.y - from_pos.y
    distance = :math.sqrt(dx * dx + dy * dy)
    
    if distance > 0.1 do
      # Normalize and set velocity
      speed = 50.0  # Base AI movement speed
      vel_x = (dx / distance) * speed
      vel_y = (dy / distance) * speed
      
      velocity = %Velocity{linear_x: vel_x, linear_y: vel_y, linear_z: 0.0}
      update_component(entity_id, Velocity, velocity)
    end
  end
  
  defp move_randomly(entity_id) do
    # Random movement direction
    angle = :rand.uniform() * 2 * :math.pi()
    speed = 25.0
    
    velocity = %Velocity{
      linear_x: :math.cos(angle) * speed,
      linear_y: :math.sin(angle) * speed,
      linear_z: 0.0
    }
    
    update_component(entity_id, Velocity, velocity)
  end
  
  defp execute_attack(entity_id, target_id) do
    # Use combat system to execute attack
    case get_component(entity_id, Combat) do
      {:ok, combat} ->
        # Find a usable ability
        available_abilities = Enum.filter(combat.abilities, fn {name, _ability} ->
          Combat.can_use_ability?(combat, name)
        end)
        
        case available_abilities do
          [{ability_name, _} | _] ->
            # Queue the ability
            updated_combat = Combat.queue_ability(combat, ability_name, target_id)
            update_component(entity_id, Combat, updated_combat)
          
          [] ->
            # No abilities available, try basic attack
            :ok
        end
      
      _ -> :ok
    end
  end
  
  defp flee_from_threats(entity_id, context) do
    with {:ok, position} <- get_component(entity_id, Position),
         {:ok, perception} <- context.perception do
      
      # Find direction away from threats
      threats = Map.values(perception.detected_entities)
      |> Enum.filter(fn entity -> entity.threat_level > 0.5 end)
      
      if length(threats) > 0 do
        # Calculate average threat position
        {avg_x, avg_y} = Enum.reduce(threats, {0.0, 0.0}, fn _threat, {sum_x, sum_y} ->
          # Note: This is simplified - would need threat positions
          {sum_x, sum_y}
        end)
        
        threat_count = length(threats)
        avg_threat_x = avg_x / threat_count
        avg_threat_y = avg_y / threat_count
        
        # Move away from average threat position
        flee_x = position.x - avg_threat_x
        flee_y = position.y - avg_threat_y
        flee_distance = :math.sqrt(flee_x * flee_x + flee_y * flee_y)
        
        if flee_distance > 0 do
          speed = 75.0  # Flee faster than normal movement
          vel_x = (flee_x / flee_distance) * speed
          vel_y = (flee_y / flee_distance) * speed
          
          velocity = %Velocity{linear_x: vel_x, linear_y: vel_y, linear_z: 0.0}
          update_component(entity_id, Velocity, velocity)
        end
      end
    else
      _ -> :ok
    end
  end
  
  defp update_entity_perception(entity_id, perception, _position, _state) do
    # Find other entities within perception range
    nearby_entities = find_nearby_entities(entity_id, perception.sight_range)
    
    # Update detected entities
    Enum.reduce(nearby_entities, perception, fn {other_id, distance}, acc_perception ->
      # Determine threat level based on entity type/combat state
      threat_level = calculate_threat_level(entity_id, other_id)
      
      Perception.detect_entity(acc_perception, other_id, distance, :visual, threat_level)
    end)
  end
  
  defp find_nearby_entities(_entity_id, _range) do
    # In a real implementation, this would query nearby entities
    # For now, return empty list
    []
  end
  
  defp calculate_threat_level(entity_id, other_id) do
    # Simple threat calculation based on combat stats
    with {:ok, my_combat} <- get_component(entity_id, Combat),
         {:ok, other_combat} <- get_component(other_id, Combat),
         {:ok, other_health} <- get_component(other_id, Health) do
      
      # Higher attack power = higher threat
      attack_ratio = other_combat.attack_power / max(my_combat.armor, 1)
      
      # Lower health entities are less threatening
      health_ratio = other_health.current / other_health.maximum
      
      # Clamp between 0.0 and 1.0
      (attack_ratio * health_ratio * 0.5) |> max(0.0) |> min(1.0)
    else
      _ -> 0.1  # Default low threat
    end
  end
  
  defp coordinate_group_behavior(behavior_type, group_entities) do
    case behavior_type do
      :aggressive ->
        coordinate_pack_hunting(group_entities)
      
      :defensive ->
        coordinate_group_defense(group_entities)
      
      _ ->
        :ok  # No coordination for other types
    end
  end
  
  defp coordinate_pack_hunting(group_entities) do
    # Find common targets and coordinate attacks
    targets = Enum.flat_map(group_entities, fn entity_id ->
      case get_component(entity_id, AIController) do
        {:ok, ai} when ai.target_entity != nil -> [ai.target_entity]
        _ -> []
      end
    end)
    |> Enum.frequencies()
    
    # Focus on most targeted entity
    case Enum.max_by(targets, fn {_target, count} -> count end, fn -> nil end) do
      {primary_target, _count} ->
        set_pack_target(group_entities, primary_target)
      
      nil -> :ok
    end
  end
  
  defp set_pack_target(group_entities, primary_target) do
    # Set primary target for all pack members
    Enum.each(group_entities, fn entity_id ->
      case get_component(entity_id, AIController) do
        {:ok, ai} ->
          updated_ai = AIController.set_target(ai, primary_target)
          update_component(entity_id, AIController, updated_ai)
        
        _ -> :ok
      end
    end)
  end
  
  defp coordinate_group_defense(group_entities) do
    # Form defensive positions around group center
    positions = Enum.map(group_entities, fn entity_id ->
      case get_component(entity_id, Position) do
        {:ok, pos} -> {entity_id, pos}
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    
    if length(positions) > 1 do
      # Calculate group center
      {sum_x, sum_y} = Enum.reduce(positions, {0.0, 0.0}, fn {_id, pos}, {sx, sy} ->
        {sx + pos.x, sy + pos.y}
      end)
      
      count = length(positions)
      center_x = sum_x / count
      center_y = sum_y / count
      
      # Assign defensive positions around center
      Enum.with_index(positions)
      |> Enum.each(fn {{entity_id, _pos}, index} ->
        angle = (index / count) * 2 * :math.pi()
        radius = 30.0  # Defensive formation radius
        
        target_x = center_x + :math.cos(angle) * radius
        target_y = center_y + :math.sin(angle) * radius
        
        # Move towards defensive position
        move_towards_point(entity_id, %{x: target_x, y: target_y})
      end)
    end
  end
  
  defp handle_behavior_failure(entity_id, ai_controller) do
    # Reset AI state on behavior failure
    updated_ai = AIController.change_state(ai_controller, :idle)
    |> AIController.clear_target()
    
    update_component(entity_id, AIController, updated_ai)
  end
  
  defp get_attack_range(%Combat{abilities: abilities}) do
    # Get maximum range from all abilities
    abilities
    |> Map.values()
    |> Enum.map(fn ability -> Map.get(ability, :range, 1.0) end)
    |> Enum.max(fn -> 1.0 end)
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
  
  # Public API for AI control
  
  @doc """
  Enable or disable global AI processing.
  """
  def set_ai_enabled(state, enabled) when is_boolean(enabled) do
    %{state | global_ai_enabled: enabled}
  end
  
  @doc """
  Set AI decision making frequency.
  """
  def set_decision_frequency(state, frequency) when frequency > 0 do
    %{state | decision_frequency: frequency}
  end
  
  @doc """
  Enable or disable pathfinding.
  """
  def set_pathfinding_enabled(state, enabled) when is_boolean(enabled) do
    %{state | pathfinding_enabled: enabled}
  end
  
  @doc """
  Get AI behavior statistics.
  """
  def get_behavior_stats(state) do
    state.behavior_stats
  end
end