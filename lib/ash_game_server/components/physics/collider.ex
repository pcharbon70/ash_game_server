defmodule AshGameServer.Components.Physics.Collider do
  @moduledoc """
  Collider component for collision detection.
  
  Defines collision shapes and properties for physics interactions.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type collider_type :: :sphere | :box | :capsule | :mesh
  @type collision_layer :: atom()
  
  @type t :: %__MODULE__{
    type: collider_type(),
    radius: float(),
    width: float(),
    height: float(),
    depth: float(),
    offset_x: float(),
    offset_y: float(),
    offset_z: float(),
    is_trigger: boolean(),
    collision_layers: [collision_layer()],
    collision_mask: [collision_layer()],
    material: map() | nil
  }
  
  defstruct [
    type: :sphere,
    radius: 1.0,
    width: 1.0,
    height: 1.0,
    depth: 1.0,
    offset_x: 0.0,
    offset_y: 0.0,
    offset_z: 0.0,
    is_trigger: false,
    collision_layers: [:default],
    collision_mask: [:default],
    material: nil
  ]
  
  @impl true
  def validate(%__MODULE__{} = collider) do
    with :ok <- validate_dimensions(collider),
         :ok <- validate_layers(collider) do
    end
  end
  
  defp validate_dimensions(%__MODULE__{radius: r, width: w, height: h, depth: d}) do
    cond do
      r <= 0.0 -> {:error, "Collider radius must be positive"}
      w <= 0.0 -> {:error, "Collider width must be positive"}
      h <= 0.0 -> {:error, "Collider height must be positive"}
      d <= 0.0 -> {:error, "Collider depth must be positive"}
      true -> :ok
    end
  end
  
  defp validate_layers(%__MODULE__{collision_layers: layers, collision_mask: mask}) do
    cond do
      not is_list(layers) or layers == [] ->
        {:error, "Collision layers must be a non-empty list"}
      not is_list(mask) or mask == [] ->
        {:error, "Collision mask must be a non-empty list"}
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = collider) do
    %{
      type: collider.type,
      radius: Float.round(collider.radius * 1.0, 3),
      width: Float.round(collider.width * 1.0, 3),
      height: Float.round(collider.height * 1.0, 3),
      depth: Float.round(collider.depth * 1.0, 3),
      offset_x: Float.round(collider.offset_x * 1.0, 3),
      offset_y: Float.round(collider.offset_y * 1.0, 3),
      offset_z: Float.round(collider.offset_z * 1.0, 3),
      is_trigger: collider.is_trigger,
      collision_layers: collider.collision_layers,
      collision_mask: collider.collision_mask,
      material: collider.material
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      type: Map.get(data, :type, :sphere),
      radius: max(Map.get(data, :radius, 1.0) * 1.0, 0.01),
      width: max(Map.get(data, :width, 1.0) * 1.0, 0.01),
      height: max(Map.get(data, :height, 1.0) * 1.0, 0.01),
      depth: max(Map.get(data, :depth, 1.0) * 1.0, 0.01),
      offset_x: Map.get(data, :offset_x, 0.0) * 1.0,
      offset_y: Map.get(data, :offset_y, 0.0) * 1.0,
      offset_z: Map.get(data, :offset_z, 0.0) * 1.0,
      is_trigger: Map.get(data, :is_trigger, false),
      collision_layers: Map.get(data, :collision_layers, [:default]),
      collision_mask: Map.get(data, :collision_mask, [:default]),
      material: Map.get(data, :material)
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a sphere collider.
  """
  def sphere(radius \\ 1.0) do
    %__MODULE__{
      type: :sphere,
      radius: radius
    }
  end
  
  @doc """
  Create a box collider.
  """
  def box(width \\ 1.0, height \\ 1.0, depth \\ 1.0) do
    %__MODULE__{
      type: :box,
      width: width,
      height: height,
      depth: depth
    }
  end
  
  @doc """
  Create a capsule collider.
  """
  def capsule(radius \\ 0.5, height \\ 2.0) do
    %__MODULE__{
      type: :capsule,
      radius: radius,
      height: height
    }
  end
  
  @doc """
  Set collider as trigger (no collision response).
  """
  def set_trigger(%__MODULE__{} = collider, is_trigger \\ true) do
    %__MODULE__{collider | is_trigger: is_trigger}
  end
  
  @doc """
  Set collision layers and mask.
  """
  def set_collision_layers(%__MODULE__{} = collider, layers, mask \\ nil) do
    %__MODULE__{collider |
      collision_layers: layers,
      collision_mask: mask || layers
    }
  end
  
  @doc """
  Set collider offset from entity position.
  """
  def set_offset(%__MODULE__{} = collider, x \\ 0.0, y \\ 0.0, z \\ 0.0) do
    %__MODULE__{collider |
      offset_x: x,
      offset_y: y,
      offset_z: z
    }
  end
  
  @doc """
  Set physics material properties.
  """
  def set_material(%__MODULE__{} = collider, material) when is_map(material) do
    %__MODULE__{collider | material: material}
  end
  
  @doc """
  Check if collider should interact with another collider's layers.
  """
  def can_collide?(%__MODULE__{} = collider1, %__MODULE__{} = collider2) do
    # Check if either collider's mask includes the other's layers
    Enum.any?(collider1.collision_mask, fn layer ->
      layer in collider2.collision_layers
    end) or
    Enum.any?(collider2.collision_mask, fn layer ->
      layer in collider1.collision_layers
    end)
  end
  
  @doc """
  Get the effective bounds of the collider.
  """
  def get_bounds(%__MODULE__{type: :sphere} = collider) do
    %{
      min_x: -collider.radius,
      max_x: collider.radius,
      min_y: -collider.radius,
      max_y: collider.radius,
      min_z: -collider.radius,
      max_z: collider.radius
    }
  end
  
  def get_bounds(%__MODULE__{type: :box} = collider) do
    half_w = collider.width * 0.5
    half_h = collider.height * 0.5
    half_d = collider.depth * 0.5
    
    %{
      min_x: -half_w,
      max_x: half_w,
      min_y: -half_h,
      max_y: half_h,
      min_z: -half_d,
      max_z: half_d
    }
  end
  
  def get_bounds(%__MODULE__{type: :capsule} = collider) do
    half_h = (collider.height - 2 * collider.radius) * 0.5
    
    %{
      min_x: -collider.radius,
      max_x: collider.radius,
      min_y: -collider.radius - half_h,
      max_y: collider.radius + half_h,
      min_z: -collider.radius,
      max_z: collider.radius
    }
  end
end