defmodule AshGameServer.Systems.CombatSystem do
  @moduledoc """
  Combat System for handling damage calculation, targeting, and combat mechanics.
  
  Processes entities with combat-related components to handle damage dealing,
  status effects, ability execution, and combat state management.
  """
  
  use AshGameServer.Systems.SystemBehaviour
  
  alias AshGameServer.Components.Gameplay.{Health, Combat, StatusEffect}
  
  @type combat_state :: %{
    combat_log: [combat_event()],
    max_log_entries: pos_integer(),
    damage_modifiers: %{atom() => float()},
    global_cooldown: float()
  }
  
  @type combat_event :: %{
    timestamp: integer(),
    attacker_id: String.t() | nil,
    target_id: String.t(),
    ability_name: atom() | nil,
    damage_type: atom(),
    damage_amount: integer(),
    was_critical: boolean(),
    status_effects: [atom()]
  }
  
  @type damage_calculation :: %{
    base_damage: integer(),
    final_damage: integer(),
    damage_type: atom(),
    is_critical: boolean(),
    blocked: boolean(),
    absorbed: integer()
  }
  
  @impl true
  def init(_opts) do
    {:ok, %{
      combat_log: [],
      max_log_entries: 1000,
      damage_modifiers: %{
        physical: 1.0,
        magical: 1.0,
        fire: 1.0,
        ice: 1.0,
        poison: 1.0
      },
      global_cooldown: 1000.0  # milliseconds
    }}
  end
  
  @impl true
  def priority, do: 90
  
  @impl true
  def required_components, do: [Health, Combat]
  
  @impl true
  def execute(entities, state) do
    # Process each entity with combat components
    Enum.each(entities, fn {entity_id, components} ->
      process_entity(entity_id, components, state)
    end)
    
    # Process damage over time effects
    process_damage_over_time(state)
    
    # Process ability cooldowns
    process_cooldowns(state)
    
    # Process combat state updates
    process_combat_states(state)
    
    {:ok, state}
  end
  
  @impl true
  def process_entity(entity_id, components, state) do
    with {:ok, combat} <- get_component(entity_id, Combat),
         {:ok, health} <- get_component(entity_id, Health) do
      
      # Process queued abilities
      updated_combat = process_ability_queue(entity_id, combat, state)
      
      # Process ongoing effects
      updated_health = process_status_effects(entity_id, health, state)
      
      # Update components
      update_component(entity_id, Combat, updated_combat)
      update_component(entity_id, Health, updated_health)
    else
      _ -> :skip
    end
    
    {:ok, components}
  end
  
  # Public API for combat actions
  
  @doc """
  Execute an ability from one entity targeting another.
  """
  def execute_ability(attacker_id, target_id, ability_name, state) do
    with {:ok, attacker_combat} <- get_component(attacker_id, Combat),
         {:ok, ability} <- get_ability(attacker_combat, ability_name),
         :ok <- check_ability_conditions(attacker_id, ability, state) do
      
      # Calculate damage
      damage_calc = calculate_damage(attacker_id, target_id, ability, state)
      
      # Apply damage
      apply_damage_calc(target_id, damage_calc, state)
      
      # Apply status effects
      apply_status_effects(target_id, ability.status_effects, attacker_id, state)
      
      # Update attacker combat state
      updated_combat = use_ability(attacker_combat, ability_name)
      update_component(attacker_id, Combat, updated_combat)
      
      # Log combat event
      log_combat_event(attacker_id, target_id, ability_name, damage_calc, state)
      
      {:ok, damage_calc}
    else
      error -> error
    end
  end
  
  @doc """
  Apply direct damage to a target.
  """
  def apply_damage(target_id, damage_amount, damage_type \\ :physical, _attacker_id \\ nil) do
    damage_calc = %{
      base_damage: damage_amount,
      final_damage: damage_amount,
      damage_type: damage_type,
      is_critical: false,
      blocked: false,
      absorbed: 0
    }
    
    apply_damage(target_id, damage_calc, %{})
  end
  
  @doc """
  Heal a target entity.
  """
  def heal(target_id, heal_amount, healer_id \\ nil) do
    case get_component(target_id, Health) do
      {:ok, health} ->
        new_current = min(health.current + heal_amount, health.maximum)
        updated_health = %Health{health | current: new_current}
        
        update_component(target_id, Health, updated_health)
        
        # Log healing event
        event = %{
          timestamp: System.monotonic_time(),
          attacker_id: healer_id,
          target_id: target_id,
          ability_name: :heal,
          damage_type: :healing,
          damage_amount: -heal_amount,
          was_critical: false,
          status_effects: []
        }
        
        {:ok, event}
      
      error -> error
    end
  end
  
  # Private functions
  
  defp process_damage_over_time(_state) do
    # In a real implementation, this would query entities with StatusEffect components
    # For now, just return :ok
    :ok
  end
  
  defp process_dot_effects(entity_id, status_effect, _state) do
    Enum.each(status_effect.active_effects, fn effect ->
      if effect.type == :damage_over_time and effect.tick_timer <= 0 do
        apply_damage(entity_id, effect.damage_per_tick, effect.damage_type)
        
        # Reset tick timer
        updated_effect = %{effect | tick_timer: effect.tick_interval}
        update_status_effect(entity_id, effect.id, updated_effect)
      end
    end)
  end
  
  defp process_cooldowns(_state) do
    # In a real implementation, this would query entities with Combat components
    # For now, just return :ok
    :ok
  end
  
  defp process_combat_states(_state) do
    # In a real implementation, this would query entities with Combat and Health components
    # For now, just return :ok
    :ok
  end
  
  defp calculate_damage(attacker_id, target_id, ability, state) do
    # Get attacker combat stats
    attacker_combat = case get_component(attacker_id, Combat) do
      {:ok, combat} -> combat
      _ -> %Combat{}
    end
    
    # Get target defense stats
    target_combat = case get_component(target_id, Combat) do
      {:ok, combat} -> combat
      _ -> %Combat{}
    end
    
    # Base damage calculation
    base_damage = ability.base_damage + 
                  (attacker_combat.attack_power * ability.attack_power_scaling)
    
    # Apply damage type modifier
    type_modifier = Map.get(state.damage_modifiers, ability.damage_type, 1.0)
    modified_damage = base_damage * type_modifier
    
    # Apply defense
    defense_value = get_defense_for_type(target_combat, ability.damage_type)
    damage_after_defense = max(1, modified_damage - defense_value)
    
    # Critical hit calculation
    crit_chance = attacker_combat.critical_chance
    is_critical = :rand.uniform() < crit_chance
    
    final_damage = if is_critical do
      damage_after_defense * attacker_combat.critical_multiplier
    else
      damage_after_defense
    end
    
    %{
      base_damage: trunc(base_damage),
      final_damage: trunc(final_damage),
      damage_type: ability.damage_type,
      is_critical: is_critical,
      blocked: false,
      absorbed: 0
    }
  end
  
  defp apply_damage_calc(target_id, damage_calc, _state) do
    case get_component(target_id, Health) do
      {:ok, health} ->
        new_current = max(0, health.current - damage_calc.final_damage)
        updated_health = %Health{health | current: new_current}
        
        update_component(target_id, Health, updated_health)
        
        {:ok, damage_calc}
      
      error -> error
    end
  end
  
  defp apply_status_effects(_target_id, [], _attacker_id, _state), do: :ok
  defp apply_status_effects(target_id, status_effects, attacker_id, _state) do
    Enum.each(status_effects, fn effect_data ->
      add_status_effect(target_id, effect_data, attacker_id)
    end)
  end
  
  defp get_ability(%Combat{abilities: abilities}, ability_name) do
    case Map.get(abilities, ability_name) do
      nil -> {:error, :ability_not_found}
      ability -> {:ok, ability}
    end
  end
  
  defp check_ability_conditions(attacker_id, ability, _state) do
    case get_component(attacker_id, Combat) do
      {:ok, combat} ->
        cond do
          on_cooldown?(combat, ability.name) ->
            {:error, :ability_on_cooldown}
          
          not has_sufficient_resources?(combat, ability) ->
            {:error, :insufficient_resources}
          
          true ->
            :ok
        end
      
      _ -> {:error, :no_combat_component}
    end
  end
  
  defp on_cooldown?(%Combat{cooldowns: cooldowns}, ability_name) do
    Map.get(cooldowns, ability_name, 0.0) > 0.0
  end
  
  defp has_sufficient_resources?(%Combat{mana: mana}, %{mana_cost: cost}) do
    mana >= cost
  end
  defp has_sufficient_resources?(_combat, _ability), do: true
  
  defp use_ability(%Combat{} = combat, ability_name) do
    case get_ability(combat, ability_name) do
      {:ok, ability} ->
        # Set cooldown
        updated_cooldowns = Map.put(combat.cooldowns, ability_name, ability.cooldown)
        
        # Consume resources
        updated_mana = max(0, combat.mana - ability.mana_cost)
        
        %Combat{combat |
          cooldowns: updated_cooldowns,
          mana: updated_mana,
          last_ability_time: System.monotonic_time()
        }
      
      _ ->
        combat
    end
  end
  
  defp update_cooldowns(%Combat{} = combat, delta_ms) do
    updated_cooldowns = Map.new(combat.cooldowns, fn {ability, time} ->
      {ability, max(0.0, time - delta_ms)}
    end)
    
    %Combat{combat | cooldowns: updated_cooldowns}
  end
  
  defp update_combat_state(%Combat{} = combat, %Health{current: hp, maximum: max_hp}) do
    # Determine combat state based on health percentage
    health_percent = hp / max_hp
    
    new_state = cond do
      hp <= 0 -> :dead
      health_percent < 0.25 -> :critical
      health_percent < 0.5 -> :injured
      true -> :healthy
    end
    
    %Combat{combat | state: new_state}
  end
  
  defp get_defense_for_type(%Combat{} = combat, damage_type) do
    case damage_type do
      :physical -> combat.armor
      :magical -> combat.magic_resistance
      _ -> combat.armor * 0.5  # Generic resistance
    end
  end
  
  defp log_combat_event(attacker_id, target_id, ability_name, damage_calc, state) do
    event = %{
      timestamp: System.monotonic_time(),
      attacker_id: attacker_id,
      target_id: target_id,
      ability_name: ability_name,
      damage_type: damage_calc.damage_type,
      damage_amount: damage_calc.final_damage,
      was_critical: damage_calc.is_critical,
      status_effects: []
    }
    
    # Add to combat log (maintain max size)
    updated_log = [event | state.combat_log]
    |> Enum.take(state.max_log_entries)
    
    %{state | combat_log: updated_log}
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
  
  defp add_status_effect(entity_id, effect_data, source_id) do
    case get_component(entity_id, StatusEffect) do
      {:ok, status_effect} ->
        updated_status = StatusEffect.add_effect(status_effect, effect_data, source_id)
        update_component(entity_id, StatusEffect, updated_status)
      
      _ ->
        # Create new status effect component
        new_status = StatusEffect.new()
        |> StatusEffect.add_effect(effect_data, source_id)
        update_component(entity_id, StatusEffect, new_status)
    end
  end
  
  defp update_status_effect(entity_id, effect_id, updated_effect) do
    case get_component(entity_id, StatusEffect) do
      {:ok, status_effect} ->
        updated_status = StatusEffect.update_effect(status_effect, effect_id, updated_effect)
        update_component(entity_id, StatusEffect, updated_status)
      
      _ ->
        :error
    end
  end
  
  defp process_ability_queue(_entity_id, %Combat{ability_queue: []} = combat, _state) do
    combat
  end
  
  defp process_ability_queue(entity_id, %Combat{ability_queue: [ability | rest]} = combat, state) do
    case execute_queued_ability(entity_id, ability, state) do
      :ok ->
        %Combat{combat | ability_queue: rest}
      :wait ->
        combat  # Keep ability in queue
      :error ->
        %Combat{combat | ability_queue: rest}  # Remove failed ability
    end
  end
  
  defp execute_queued_ability(entity_id, queued_ability, _state) do
    # Check if conditions are met to execute the ability
    with {:ok, combat} <- get_component(entity_id, Combat),
         {:ok, ability} <- get_ability(combat, queued_ability.name),
         :ok <- check_ability_conditions(entity_id, ability, %{}) do
      
      # Execute the ability
      execute_ability(entity_id, queued_ability.target_id, ability.name, %{})
      :ok
    else
      {:error, :ability_on_cooldown} -> :wait
      _ -> :error
    end
  end
  
  defp process_status_effects(entity_id, health, _state) do
    case get_component(entity_id, StatusEffect) do
      {:ok, status_effect} ->
        # Update status effects and apply their effects to health
        updated_status = StatusEffect.update(status_effect, 16.0)  # 60fps
        update_component(entity_id, StatusEffect, updated_status)
        
        # Apply health modifications from effects
        apply_status_health_effects(health, updated_status)
      
      _ ->
        health
    end
  end
  
  defp apply_status_health_effects(health, status_effect) do
    # Apply regeneration effects
    regen_amount = StatusEffect.get_total_regeneration(status_effect)
    
    if regen_amount != 0 do
      new_current = health.current + regen_amount
      |> max(0)
      |> min(health.maximum)
      
      %Health{health | current: new_current}
    else
      health
    end
  end
end