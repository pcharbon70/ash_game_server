defmodule AshGameServer.Components.Rendering.LOD do
  @moduledoc """
  Level of Detail component for optimizing rendering based on distance.
  
  Manages multiple detail levels and automatic switching.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type lod_level :: :high | :medium | :low | :billboard | non_neg_integer()
  
  @type t :: %__MODULE__{
    current_level: lod_level(),
    levels: %{lod_level() => float()},  # level => distance threshold
    bias: float(),
    force_level: lod_level() | nil
  }
  
  defstruct [
    current_level: :high,
    levels: %{
      high: 50.0,
      medium: 100.0,
      low: 200.0,
      billboard: 500.0
    },
    bias: 1.0,
    force_level: nil
  ]
  
  @impl true
  def validate(%__MODULE__{} = lod) do
    cond do
      not is_map(lod.levels) ->
        {:error, "LOD levels must be a map"}
      
      not valid_levels?(lod.levels) ->
        {:error, "LOD levels must have positive distance thresholds"}
      
      lod.bias <= 0 ->
        {:error, "LOD bias must be positive"}
      
      true ->
        :ok
    end
  end
  
  defp valid_levels?(levels) do
    Enum.all?(levels, fn {_level, distance} ->
      is_number(distance) and distance > 0
    end)
  end
  
  @impl true
  def serialize(%__MODULE__{} = lod) do
    %{
      current_level: lod.current_level,
      levels: serialize_levels(lod.levels),
      bias: Float.round(lod.bias * 1.0, 2),
      force_level: lod.force_level
    }
  end
  
  defp serialize_levels(levels) do
    Map.new(levels, fn {level, distance} ->
      {level, Float.round(distance * 1.0, 1)}
    end)
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      current_level: Map.get(data, :current_level, :high),
      levels: Map.get(data, :levels, default_levels()),
      bias: Map.get(data, :bias, 1.0) * 1.0,
      force_level: Map.get(data, :force_level)
    }}
  end
  
  defp default_levels do
    %{
      high: 50.0,
      medium: 100.0,
      low: 200.0,
      billboard: 500.0
    }
  end
  
  # Helper functions
  
  @doc """
  Create LOD with custom distance thresholds.
  """
  def new(levels \\ %{}) do
    %__MODULE__{
      levels: Map.merge(default_levels(), levels)
    }
  end
  
  @doc """
  Update LOD level based on distance.
  """
  def update_level(%__MODULE__{force_level: level} = lod, _distance) when level != nil do
    %__MODULE__{lod | current_level: level}
  end
  
  def update_level(%__MODULE__{} = lod, distance) do
    adjusted_distance = distance / lod.bias
    
    # Sort levels by distance threshold
    sorted_levels = lod.levels
    |> Enum.sort_by(fn {_level, dist} -> dist end)
    
    # Find appropriate level
    new_level = sorted_levels
    |> Enum.find(fn {_level, threshold} -> 
      adjusted_distance <= threshold
    end)
    |> case do
      {level, _} -> level
      nil -> :billboard  # Furthest level as fallback
    end
    
    %__MODULE__{lod | current_level: new_level}
  end
  
  @doc """
  Force a specific LOD level.
  """
  def force_level(%__MODULE__{} = lod, level) do
    %__MODULE__{lod | 
      force_level: level,
      current_level: level || lod.current_level
    }
  end
  
  @doc """
  Clear forced LOD level.
  """
  def auto_level(%__MODULE__{} = lod) do
    %__MODULE__{lod | force_level: nil}
  end
  
  @doc """
  Set LOD bias (higher = prefer lower detail).
  """
  def set_bias(%__MODULE__{} = lod, bias) when bias > 0 do
    %__MODULE__{lod | bias: bias}
  end
  
  @doc """
  Check if at highest detail level.
  """
  def high_detail?(%__MODULE__{current_level: :high}), do: true
  def high_detail?(%__MODULE__{}), do: false
  
  @doc """
  Check if at lowest detail level.
  """
  def low_detail?(%__MODULE__{current_level: level}) do
    level in [:billboard, :low]
  end
end