defmodule AshGameServer.Components.Transform.Scale do
  @moduledoc """
  Scale component for entity size in 3D space.
  
  Stores scaling factors for x, y, z axes.
  A value of 1.0 represents normal size.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    x: float(),
    y: float(),
    z: float()
  }
  
  defstruct x: 1.0, y: 1.0, z: 1.0
  
  @impl true
  def validate(%__MODULE__{} = scale) do
    cond do
      not is_number(scale.x) ->
        {:error, "Scale x must be a number"}
      
      not is_number(scale.y) ->
        {:error, "Scale y must be a number"}
      
      not is_number(scale.z) ->
        {:error, "Scale z must be a number"}
      
      scale.x < 0 ->
        {:error, "Scale x cannot be negative"}
      
      scale.y < 0 ->
        {:error, "Scale y cannot be negative"}
      
      scale.z < 0 ->
        {:error, "Scale z cannot be negative"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = scale) do
    %{
      x: Float.round(scale.x * 1.0, 3),
      y: Float.round(scale.y * 1.0, 3),
      z: Float.round(scale.z * 1.0, 3)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      x: max(0.0, Map.get(data, :x, 1.0) * 1.0),
      y: max(0.0, Map.get(data, :y, 1.0) * 1.0),
      z: max(0.0, Map.get(data, :z, 1.0) * 1.0)
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a new scale with uniform scaling.
  """
  def uniform(factor) when is_number(factor) and factor >= 0 do
    %__MODULE__{x: factor, y: factor, z: factor}
  end
  
  @doc """
  Create a new scale with no scaling (1.0).
  """
  def identity do
    %__MODULE__{x: 1.0, y: 1.0, z: 1.0}
  end
  
  @doc """
  Create a new scale with specific values.
  """
  def new(x, y, z \\ 1.0) do
    %__MODULE__{
      x: max(0.0, x * 1.0),
      y: max(0.0, y * 1.0),
      z: max(0.0, z * 1.0)
    }
  end
  
  @doc """
  Multiply two scales together.
  """
  def multiply(%__MODULE__{} = s1, %__MODULE__{} = s2) do
    %__MODULE__{
      x: s1.x * s2.x,
      y: s1.y * s2.y,
      z: s1.z * s2.z
    }
  end
  
  @doc """
  Divide one scale by another.
  """
  def divide(%__MODULE__{} = s1, %__MODULE__{} = s2) do
    %__MODULE__{
      x: safe_divide(s1.x, s2.x),
      y: safe_divide(s1.y, s2.y),
      z: safe_divide(s1.z, s2.z)
    }
  end
  
  @doc """
  Linear interpolation between two scales.
  """
  def lerp(%__MODULE__{} = s1, %__MODULE__{} = s2, t) when is_number(t) do
    t = max(0.0, min(1.0, t))
    
    %__MODULE__{
      x: s1.x + (s2.x - s1.x) * t,
      y: s1.y + (s2.y - s1.y) * t,
      z: s1.z + (s2.z - s1.z) * t
    }
  end
  
  @doc """
  Check if scale is uniform (all axes have same value).
  """
  def uniform?(%__MODULE__{} = scale) do
    abs(scale.x - scale.y) < 0.001 and abs(scale.y - scale.z) < 0.001
  end
  
  @doc """
  Get the average scale factor.
  """
  def average(%__MODULE__{} = scale) do
    (scale.x + scale.y + scale.z) / 3.0
  end
  
  @doc """
  Get the volume multiplier (x * y * z).
  """
  def volume(%__MODULE__{} = scale) do
    scale.x * scale.y * scale.z
  end
  
  @doc """
  Clamp scale values to a range.
  """
  def clamp(%__MODULE__{} = scale, min_val, max_val) 
      when is_number(min_val) and is_number(max_val) and min_val >= 0 do
    %__MODULE__{
      x: max(min_val, min(max_val, scale.x)),
      y: max(min_val, min(max_val, scale.y)),
      z: max(min_val, min(max_val, scale.z))
    }
  end
  
  # Private helpers
  
  defp safe_divide(a, b) when b == 0, do: a
  defp safe_divide(a, b), do: a / b
end