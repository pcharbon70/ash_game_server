defmodule AshGameServer.Components.Gameplay.Combat do
  @moduledoc """
  Combat component for managing combat statistics and abilities.
  
  Handles attack power, defense, critical hits, abilities, and combat state.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type combat_state :: :healthy | :injured | :critical | :dead | :stunned | :incapacitated
  @type damage_type :: :physical | :magical | :fire | :ice | :poison | :holy | :dark
  
  @type ability :: %{
    name: atom(),
    base_damage: integer(),
    damage_type: damage_type(),
    attack_power_scaling: float(),
    mana_cost: integer(),
    cooldown: float(),
    range: float(),
    area_of_effect: float(),
    status_effects: [map()]
  }
  
  @type queued_ability :: %{
    name: atom(),
    target_id: String.t() | nil,
    queued_at: integer()
  }
  
  @type t :: %__MODULE__{
    attack_power: integer(),
    spell_power: integer(),
    armor: integer(),
    magic_resistance: integer(),
    critical_chance: float(),
    critical_multiplier: float(),
    accuracy: float(),
    evasion: float(),
    mana: integer(),
    max_mana: integer(),
    mana_regeneration: integer(),
    state: combat_state(),
    abilities: %{atom() => ability()},
    cooldowns: %{atom() => float()},
    ability_queue: [queued_ability()],
    last_ability_time: integer(),
    combat_tags: [atom()]
  }
  
  defstruct [
    attack_power: 10,
    spell_power: 10,
    armor: 5,
    magic_resistance: 5,
    critical_chance: 0.05,
    critical_multiplier: 2.0,
    accuracy: 0.95,
    evasion: 0.05,
    mana: 100,
    max_mana: 100,
    mana_regeneration: 5,
    state: :healthy,
    abilities: %{},
    cooldowns: %{},
    ability_queue: [],
    last_ability_time: 0,
    combat_tags: []
  ]
  
  @impl true
  def validate(%__MODULE__{} = combat) do
    with :ok <- validate_stats(combat),
         :ok <- validate_percentages(combat),
         :ok <- validate_mana(combat) do
      validate_abilities(combat)
    end
  end
  
  defp validate_stats(%__MODULE__{attack_power: ap, spell_power: sp, armor: armor, magic_resistance: mr}) do
    cond do
      ap < 0 -> {:error, "Attack power cannot be negative"}
      sp < 0 -> {:error, "Spell power cannot be negative"}
      armor < 0 -> {:error, "Armor cannot be negative"}
      mr < 0 -> {:error, "Magic resistance cannot be negative"}
      true -> :ok
    end
  end
  
  defp validate_percentages(%__MODULE__{critical_chance: cc, accuracy: acc, evasion: eva}) do
    cond do
      cc < 0.0 or cc > 1.0 -> {:error, "Critical chance must be between 0.0 and 1.0"}
      acc < 0.0 or acc > 1.0 -> {:error, "Accuracy must be between 0.0 and 1.0"}
      eva < 0.0 or eva > 1.0 -> {:error, "Evasion must be between 0.0 and 1.0"}
      true -> :ok
    end
  end
  
  defp validate_mana(%__MODULE__{mana: mana, max_mana: max_mana, mana_regeneration: regen}) do
    cond do
      max_mana <= 0 -> {:error, "Max mana must be positive"}
      mana < 0 -> {:error, "Mana cannot be negative"}
      mana > max_mana -> {:error, "Mana cannot exceed max mana"}
      regen < 0 -> {:error, "Mana regeneration cannot be negative"}
      true -> :ok
    end
  end
  
  defp validate_abilities(%__MODULE__{abilities: abilities}) do
    Enum.reduce_while(abilities, :ok, fn {name, ability}, _acc ->
      case validate_ability(name, ability) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_ability(name, ability) when is_map(ability) do
    required_keys = [:name, :base_damage, :damage_type, :attack_power_scaling, :mana_cost, :cooldown]
    
    missing_keys = Enum.filter(required_keys, fn key ->
      not Map.has_key?(ability, key)
    end)
    
    case missing_keys do
      [] ->
        cond do
          ability.base_damage < 0 -> {:error, "Ability #{name} base damage cannot be negative"}
          ability.mana_cost < 0 -> {:error, "Ability #{name} mana cost cannot be negative"}
          ability.cooldown < 0 -> {:error, "Ability #{name} cooldown cannot be negative"}
          true -> :ok
        end
      
      _ ->
        {:error, "Ability #{name} missing required keys: #{inspect(missing_keys)}"}
    end
  end
  defp validate_ability(name, _), do: {:error, "Ability #{name} must be a map"}
  
  @impl true
  def serialize(%__MODULE__{} = combat) do
    %{
      attack_power: combat.attack_power,
      spell_power: combat.spell_power,
      armor: combat.armor,
      magic_resistance: combat.magic_resistance,
      critical_chance: Float.round(combat.critical_chance * 1.0, 3),
      critical_multiplier: Float.round(combat.critical_multiplier * 1.0, 2),
      accuracy: Float.round(combat.accuracy * 1.0, 3),
      evasion: Float.round(combat.evasion * 1.0, 3),
      mana: combat.mana,
      max_mana: combat.max_mana,
      mana_regeneration: combat.mana_regeneration,
      state: combat.state,
      abilities: serialize_abilities(combat.abilities),
      cooldowns: serialize_cooldowns(combat.cooldowns),
      ability_queue: combat.ability_queue,
      last_ability_time: combat.last_ability_time,
      combat_tags: combat.combat_tags
    }
  end
  
  defp serialize_abilities(abilities) do
    Map.new(abilities, fn {name, ability} ->
      {name, %{
        name: ability.name,
        base_damage: ability.base_damage,
        damage_type: ability.damage_type,
        attack_power_scaling: Float.round(ability.attack_power_scaling * 1.0, 2),
        mana_cost: ability.mana_cost,
        cooldown: Float.round(ability.cooldown * 1.0, 1),
        range: Float.round(Map.get(ability, :range, 1.0) * 1.0, 1),
        area_of_effect: Float.round(Map.get(ability, :area_of_effect, 0.0) * 1.0, 1),
        status_effects: Map.get(ability, :status_effects, [])
      }}
    end)
  end
  
  defp serialize_cooldowns(cooldowns) do
    Map.new(cooldowns, fn {ability, time} ->
      {ability, Float.round(time * 1.0, 1)}
    end)
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      attack_power: max(Map.get(data, :attack_power, 10), 0),
      spell_power: max(Map.get(data, :spell_power, 10), 0),
      armor: max(Map.get(data, :armor, 5), 0),
      magic_resistance: max(Map.get(data, :magic_resistance, 5), 0),
      critical_chance: clamp(Map.get(data, :critical_chance, 0.05), 0.0, 1.0),
      critical_multiplier: max(Map.get(data, :critical_multiplier, 2.0), 1.0),
      accuracy: clamp(Map.get(data, :accuracy, 0.95), 0.0, 1.0),
      evasion: clamp(Map.get(data, :evasion, 0.05), 0.0, 1.0),
      mana: max(Map.get(data, :mana, 100), 0),
      max_mana: max(Map.get(data, :max_mana, 100), 1),
      mana_regeneration: max(Map.get(data, :mana_regeneration, 5), 0),
      state: Map.get(data, :state, :healthy),
      abilities: deserialize_abilities(Map.get(data, :abilities, %{})),
      cooldowns: Map.get(data, :cooldowns, %{}),
      ability_queue: Map.get(data, :ability_queue, []),
      last_ability_time: Map.get(data, :last_ability_time, 0),
      combat_tags: Map.get(data, :combat_tags, [])
    }}
  end
  
  defp deserialize_abilities(abilities) when is_map(abilities) do
    Map.new(abilities, fn {name, ability} ->
      {name, %{
        name: Map.get(ability, :name, name),
        base_damage: max(Map.get(ability, :base_damage, 0), 0),
        damage_type: Map.get(ability, :damage_type, :physical),
        attack_power_scaling: Map.get(ability, :attack_power_scaling, 0.0) * 1.0,
        mana_cost: max(Map.get(ability, :mana_cost, 0), 0),
        cooldown: max(Map.get(ability, :cooldown, 0.0) * 1.0, 0.0),
        range: max(Map.get(ability, :range, 1.0) * 1.0, 0.1),
        area_of_effect: max(Map.get(ability, :area_of_effect, 0.0) * 1.0, 0.0),
        status_effects: Map.get(ability, :status_effects, [])
      }}
    end)
  end
  defp deserialize_abilities(_), do: %{}
  
  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
  defp clamp(_value, _min, max), do: max
  
  # Helper functions
  
  @doc """
  Create a basic combat component with default stats.
  """
  def new(attack_power \\ 10, spell_power \\ 10) do
    %__MODULE__{
      attack_power: attack_power,
      spell_power: spell_power
    }
  end
  
  @doc """
  Add an ability to the combat component.
  """
  def add_ability(%__MODULE__{} = combat, ability) when is_map(ability) do
    case validate_ability(ability.name, ability) do
      :ok ->
        %__MODULE__{combat |
          abilities: Map.put(combat.abilities, ability.name, ability)
        }
      
      _ ->
        combat
    end
  end
  
  @doc """
  Remove an ability from the combat component.
  """
  def remove_ability(%__MODULE__{} = combat, ability_name) do
    %__MODULE__{combat |
      abilities: Map.delete(combat.abilities, ability_name),
      cooldowns: Map.delete(combat.cooldowns, ability_name)
    }
  end
  
  @doc """
  Set combat stats.
  """
  def set_stats(%__MODULE__{} = combat, opts \\ []) do
    %__MODULE__{combat |
      attack_power: Keyword.get(opts, :attack_power, combat.attack_power),
      spell_power: Keyword.get(opts, :spell_power, combat.spell_power),
      armor: Keyword.get(opts, :armor, combat.armor),
      magic_resistance: Keyword.get(opts, :magic_resistance, combat.magic_resistance)
    }
  end
  
  @doc """
  Set mana values.
  """
  def set_mana(%__MODULE__{} = combat, current, maximum \\ nil) do
    max_mana = maximum || combat.max_mana
    
    %__MODULE__{combat |
      mana: clamp(current, 0, max_mana),
      max_mana: max(max_mana, 1)
    }
  end
  
  @doc """
  Regenerate mana.
  """
  def regenerate_mana(%__MODULE__{} = combat, amount \\ nil) do
    regen_amount = amount || combat.mana_regeneration
    new_mana = min(combat.mana + regen_amount, combat.max_mana)
    
    %__MODULE__{combat | mana: new_mana}
  end
  
  @doc """
  Check if ability is available (not on cooldown, sufficient mana).
  """
  def can_use_ability?(%__MODULE__{} = combat, ability_name) do
    case Map.get(combat.abilities, ability_name) do
      nil ->
        false
      
      ability ->
        cooldown_ready = Map.get(combat.cooldowns, ability_name, 0.0) <= 0.0
        has_mana = combat.mana >= ability.mana_cost
        
        cooldown_ready and has_mana
    end
  end
  
  @doc """
  Queue an ability for execution.
  """
  def queue_ability(%__MODULE__{} = combat, ability_name, target_id \\ nil) do
    queued = %{
      name: ability_name,
      target_id: target_id,
      queued_at: System.monotonic_time()
    }
    
    %__MODULE__{combat |
      ability_queue: combat.ability_queue ++ [queued]
    }
  end
  
  @doc """
  Clear the ability queue.
  """
  def clear_ability_queue(%__MODULE__{} = combat) do
    %__MODULE__{combat | ability_queue: []}
  end
  
  @doc """
  Add combat tags for special effects or conditions.
  """
  def add_combat_tag(%__MODULE__{} = combat, tag) when is_atom(tag) do
    if tag in combat.combat_tags do
      combat
    else
      %__MODULE__{combat | combat_tags: [tag | combat.combat_tags]}
    end
  end
  
  @doc """
  Remove combat tag.
  """
  def remove_combat_tag(%__MODULE__{} = combat, tag) do
    %__MODULE__{combat |
      combat_tags: List.delete(combat.combat_tags, tag)
    }
  end
  
  @doc """
  Check if combat component has a specific tag.
  """
  def has_combat_tag?(%__MODULE__{} = combat, tag) do
    tag in combat.combat_tags
  end
  
  @doc """
  Calculate effective attack power for a damage type.
  """
  def get_effective_attack_power(%__MODULE__{} = combat, damage_type) do
    case damage_type do
      :magical -> combat.spell_power
      _ -> combat.attack_power
    end
  end
  
  @doc """
  Calculate effective defense for a damage type.
  """
  def get_effective_defense(%__MODULE__{} = combat, damage_type) do
    case damage_type do
      :magical -> combat.magic_resistance
      _ -> combat.armor
    end
  end
  
  @doc """
  Check if entity is in combat state.
  """
  def in_combat?(%__MODULE__{} = combat) do
    current_time = System.monotonic_time()
    time_since_ability = current_time - combat.last_ability_time
    
    # Consider in combat if used ability within last 5 seconds
    time_since_ability < 5_000_000_000  # 5 seconds in nanoseconds
  end
end