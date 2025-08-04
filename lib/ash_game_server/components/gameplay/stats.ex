defmodule AshGameServer.Components.Gameplay.Stats do
  @moduledoc """
  Stats component for entity attributes and modifiers.
  
  Manages base stats, modifiers, and calculated values.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type stat_name :: atom()
  @type modifier_type :: :flat | :percentage | :multiplier
  
  @type modifier :: %{
    value: float(),
    type: modifier_type(),
    source: term()
  }
  
  @type t :: %__MODULE__{
    base_stats: %{stat_name() => float()},
    modifiers: %{stat_name() => [modifier()]},
    calculated_stats: %{stat_name() => float()}
  }
  
  defstruct [
    base_stats: %{},
    modifiers: %{},
    calculated_stats: %{}
  ]
  
  @impl true
  def validate(%__MODULE__{} = stats) do
    with :ok <- validate_base_stats(stats.base_stats) do
      validate_modifiers(stats.modifiers)
    end
  end
  
  defp validate_base_stats(base_stats) do
    invalid = Enum.find(base_stats, fn {_name, value} ->
      not is_number(value)
    end)
    
    if invalid do
      {:error, "Invalid base stat value"}
    else
      :ok
    end
  end
  
  defp validate_modifiers(modifiers) do
    invalid = Enum.find(modifiers, fn {_stat, mods} ->
      not is_list(mods) or
      Enum.any?(mods, fn mod ->
        not is_map(mod) or
        not is_number(Map.get(mod, :value, 0)) or
        Map.get(mod, :type) not in [:flat, :percentage, :multiplier]
      end)
    end)
    
    if invalid do
      {:error, "Invalid modifier"}
    else
      :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = stats) do
    %{
      base_stats: serialize_stats(stats.base_stats),
      modifiers: serialize_modifiers(stats.modifiers),
      calculated_stats: serialize_stats(stats.calculated_stats)
    }
  end
  
  defp serialize_stats(stats) do
    Map.new(stats, fn {name, value} ->
      {name, Float.round(value * 1.0, 2)}
    end)
  end
  
  defp serialize_modifiers(modifiers) do
    Map.new(modifiers, fn {stat, mods} ->
      {stat, Enum.map(mods, &serialize_modifier/1)}
    end)
  end
  
  defp serialize_modifier(mod) do
    %{
      value: Float.round(Map.get(mod, :value, 0.0) * 1.0, 3),
      type: Map.get(mod, :type, :flat),
      source: Map.get(mod, :source)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    base_stats = deserialize_stats(Map.get(data, :base_stats, %{}))
    modifiers = deserialize_modifiers(Map.get(data, :modifiers, %{}))
    
    stats = %__MODULE__{
      base_stats: base_stats,
      modifiers: modifiers,
      calculated_stats: %{}
    }
    
    {:ok, recalculate(stats)}
  end
  
  defp deserialize_stats(stats) do
    Map.new(stats, fn {name, value} ->
      {name, value * 1.0}
    end)
  end
  
  defp deserialize_modifiers(modifiers) do
    Map.new(modifiers, fn {stat, mods} ->
      {stat, Enum.map(mods, &deserialize_modifier/1)}
    end)
  end
  
  defp deserialize_modifier(mod) do
    %{
      value: Map.get(mod, :value, 0.0) * 1.0,
      type: Map.get(mod, :type, :flat),
      source: Map.get(mod, :source)
    }
  end
  
  # Helper functions
  
  @doc """
  Create stats with default RPG attributes.
  """
  def default do
    %__MODULE__{
      base_stats: %{
        strength: 10.0,
        agility: 10.0,
        intelligence: 10.0,
        vitality: 10.0,
        luck: 10.0
      },
      modifiers: %{},
      calculated_stats: %{}
    }
    |> recalculate()
  end
  
  @doc """
  Set a base stat value.
  """
  def set_base(%__MODULE__{} = stats, stat_name, value) when is_number(value) do
    new_base = Map.put(stats.base_stats, stat_name, value * 1.0)
    %__MODULE__{stats | base_stats: new_base}
    |> recalculate()
  end
  
  @doc """
  Add a modifier to a stat.
  """
  def add_modifier(%__MODULE__{} = stats, stat_name, modifier) do
    current_mods = Map.get(stats.modifiers, stat_name, [])
    new_mods = Map.put(stats.modifiers, stat_name, [modifier | current_mods])
    
    %__MODULE__{stats | modifiers: new_mods}
    |> recalculate()
  end
  
  @doc """
  Remove modifiers from a specific source.
  """
  def remove_modifiers_by_source(%__MODULE__{} = stats, source) do
    new_modifiers = Map.new(stats.modifiers, fn {stat, mods} ->
      filtered = Enum.reject(mods, fn mod ->
        Map.get(mod, :source) == source
      end)
      {stat, filtered}
    end)
    
    %__MODULE__{stats | modifiers: new_modifiers}
    |> recalculate()
  end
  
  @doc """
  Get the final calculated value for a stat.
  """
  def get_stat(%__MODULE__{calculated_stats: calculated}, stat_name) do
    Map.get(calculated, stat_name, 0.0)
  end
  
  @doc """
  Get just the base value for a stat.
  """
  def get_base_stat(%__MODULE__{base_stats: base}, stat_name) do
    Map.get(base, stat_name, 0.0)
  end
  
  @doc """
  Recalculate all stats with modifiers.
  """
  def recalculate(%__MODULE__{} = stats) do
    all_stat_names = 
      Map.keys(stats.base_stats) ++ Map.keys(stats.modifiers)
      |> Enum.uniq()
    
    calculated = Map.new(all_stat_names, fn stat_name ->
      {stat_name, calculate_stat(stats, stat_name)}
    end)
    
    %__MODULE__{stats | calculated_stats: calculated}
  end
  
  # Private calculation helpers
  
  defp calculate_stat(%__MODULE__{} = stats, stat_name) do
    base = Map.get(stats.base_stats, stat_name, 0.0)
    modifiers = Map.get(stats.modifiers, stat_name, [])
    
    # Group modifiers by type
    {flats, percentages, multipliers} = 
      Enum.reduce(modifiers, {[], [], []}, fn mod, {f, p, m} ->
        case Map.get(mod, :type, :flat) do
          :flat -> {[Map.get(mod, :value, 0) | f], p, m}
          :percentage -> {f, [Map.get(mod, :value, 0) | p], m}
          :multiplier -> {f, p, [Map.get(mod, :value, 1) | m]}
        end
      end)
    
    # Apply in order: base + flat, then percentage, then multipliers
    with_flat = base + Enum.sum(flats)
    with_percentage = with_flat * (1.0 + Enum.sum(percentages) / 100.0)
    final = Enum.reduce(multipliers, with_percentage, fn mult, acc -> acc * mult end)
    
    max(0.0, final)
  end
end