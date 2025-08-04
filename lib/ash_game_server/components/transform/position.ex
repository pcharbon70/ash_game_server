defmodule AshGameServer.Components.Transform.Position do
  @moduledoc """
  Position component for entity spatial location in 3D space.
  
  Stores x, y, z coordinates as floats for precise positioning.
  Supports 2D games by ignoring the z coordinate.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    x: float(),
    y: float(),
    z: float()
  }
  
  defstruct x: 0.0, y: 0.0, z: 0.0
  
  @impl true
  def validate(%__MODULE__{} = position) do
    cond do
      not is_number(position.x) ->
        {:error, "Position x must be a number"}
      
      not is_number(position.y) ->
        {:error, "Position y must be a number"}
      
      not is_number(position.z) ->
        {:error, "Position z must be a number"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = position) do
    %{
      x: Float.round(position.x * 1.0, 3),
      y: Float.round(position.y * 1.0, 3),
      z: Float.round(position.z * 1.0, 3)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      x: Map.get(data, :x, 0.0) * 1.0,
      y: Map.get(data, :y, 0.0) * 1.0,
      z: Map.get(data, :z, 0.0) * 1.0
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a new position at the origin.
  """
  def origin do
    %__MODULE__{x: 0.0, y: 0.0, z: 0.0}
  end
  
  @doc """
  Create a new position with given coordinates.
  """
  def new(x, y, z \\ 0.0) do
    %__MODULE__{x: x * 1.0, y: y * 1.0, z: z * 1.0}
  end
  
  @doc """
  Calculate distance between two positions.
  """
  def distance(%__MODULE__{} = p1, %__MODULE__{} = p2) do
    dx = p2.x - p1.x
    dy = p2.y - p1.y
    dz = p2.z - p1.z
    
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  
  @doc """
  Calculate squared distance (more efficient for comparisons).
  """
  def distance_squared(%__MODULE__{} = p1, %__MODULE__{} = p2) do
    dx = p2.x - p1.x
    dy = p2.y - p1.y
    dz = p2.z - p1.z
    
    dx * dx + dy * dy + dz * dz
  end
  
  @doc """
  Add two positions together.
  """
  def add(%__MODULE__{} = p1, %__MODULE__{} = p2) do
    %__MODULE__{
      x: p1.x + p2.x,
      y: p1.y + p2.y,
      z: p1.z + p2.z
    }
  end
  
  @doc """
  Subtract one position from another.
  """
  def subtract(%__MODULE__{} = p1, %__MODULE__{} = p2) do
    %__MODULE__{
      x: p1.x - p2.x,
      y: p1.y - p2.y,
      z: p1.z - p2.z
    }
  end
  
  @doc """
  Scale a position by a scalar value.
  """
  def scale(%__MODULE__{} = position, scalar) when is_number(scalar) do
    %__MODULE__{
      x: position.x * scalar,
      y: position.y * scalar,
      z: position.z * scalar
    }
  end
  
  @doc """
  Normalize a position to unit length.
  """
  def normalize(%__MODULE__{x: x, y: y, z: z} = position) when x == 0.0 and y == 0.0 and z == 0.0, do: position
  def normalize(%__MODULE__{} = position) do
    length = :math.sqrt(position.x * position.x + position.y * position.y + position.z * position.z)
    
    %__MODULE__{
      x: position.x / length,
      y: position.y / length,
      z: position.z / length
    }
  end
  
  @doc """
  Linear interpolation between two positions.
  """
  def lerp(%__MODULE__{} = p1, %__MODULE__{} = p2, t) when is_number(t) do
    t = max(0.0, min(1.0, t))
    
    %__MODULE__{
      x: p1.x + (p2.x - p1.x) * t,
      y: p1.y + (p2.y - p1.y) * t,
      z: p1.z + (p2.z - p1.z) * t
    }
  end
end