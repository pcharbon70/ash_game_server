defmodule AshGameServer.Components.Transform.Rotation do
  @moduledoc """
  Rotation component for entity orientation in 3D space.
  
  Uses Euler angles (pitch, yaw, roll) in radians for simplicity.
  Can be converted to/from quaternions for advanced operations.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    pitch: float(),  # Rotation around X axis
    yaw: float(),    # Rotation around Y axis  
    roll: float()    # Rotation around Z axis
  }
  
  defstruct pitch: 0.0, yaw: 0.0, roll: 0.0
  
  @impl true
  def validate(%__MODULE__{} = rotation) do
    cond do
      not is_number(rotation.pitch) ->
        {:error, "Rotation pitch must be a number"}
      
      not is_number(rotation.yaw) ->
        {:error, "Rotation yaw must be a number"}
      
      not is_number(rotation.roll) ->
        {:error, "Rotation roll must be a number"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = rotation) do
    %{
      pitch: Float.round(rotation.pitch * 1.0, 4),
      yaw: Float.round(rotation.yaw * 1.0, 4),
      roll: Float.round(rotation.roll * 1.0, 4)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      pitch: Map.get(data, :pitch, 0.0) * 1.0,
      yaw: Map.get(data, :yaw, 0.0) * 1.0,
      roll: Map.get(data, :roll, 0.0) * 1.0
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a new rotation with no rotation.
  """
  def identity do
    %__MODULE__{pitch: 0.0, yaw: 0.0, roll: 0.0}
  end
  
  @doc """
  Create a new rotation from Euler angles in radians.
  """
  def from_euler(pitch, yaw, roll) do
    %__MODULE__{
      pitch: normalize_angle(pitch),
      yaw: normalize_angle(yaw),
      roll: normalize_angle(roll)
    }
  end
  
  @doc """
  Create a new rotation from Euler angles in degrees.
  """
  def from_degrees(pitch_deg, yaw_deg, roll_deg) do
    from_euler(
      degrees_to_radians(pitch_deg),
      degrees_to_radians(yaw_deg),
      degrees_to_radians(roll_deg)
    )
  end
  
  @doc """
  Convert rotation to degrees.
  """
  def to_degrees(%__MODULE__{} = rotation) do
    %{
      pitch: radians_to_degrees(rotation.pitch),
      yaw: radians_to_degrees(rotation.yaw),
      roll: radians_to_degrees(rotation.roll)
    }
  end
  
  @doc """
  Create rotation to look at a target position from current position.
  """
  def look_at(from_pos, to_pos) do
    # Calculate direction vector
    dx = to_pos.x - from_pos.x
    dy = to_pos.y - from_pos.y
    dz = to_pos.z - from_pos.z
    
    # Calculate yaw (rotation around Y axis)
    yaw = :math.atan2(dx, dz)
    
    # Calculate pitch (rotation around X axis)
    horizontal_dist = :math.sqrt(dx * dx + dz * dz)
    pitch = -:math.atan2(dy, horizontal_dist)
    
    %__MODULE__{pitch: pitch, yaw: yaw, roll: 0.0}
  end
  
  @doc """
  Combine two rotations.
  """
  def combine(%__MODULE__{} = r1, %__MODULE__{} = r2) do
    %__MODULE__{
      pitch: normalize_angle(r1.pitch + r2.pitch),
      yaw: normalize_angle(r1.yaw + r2.yaw),
      roll: normalize_angle(r1.roll + r2.roll)
    }
  end
  
  @doc """
  Invert a rotation.
  """
  def inverse(%__MODULE__{} = rotation) do
    %__MODULE__{
      pitch: -rotation.pitch,
      yaw: -rotation.yaw,
      roll: -rotation.roll
    }
  end
  
  @doc """
  Linear interpolation between two rotations.
  """
  def lerp(%__MODULE__{} = r1, %__MODULE__{} = r2, t) when is_number(t) do
    t = max(0.0, min(1.0, t))
    
    %__MODULE__{
      pitch: lerp_angle(r1.pitch, r2.pitch, t),
      yaw: lerp_angle(r1.yaw, r2.yaw, t),
      roll: lerp_angle(r1.roll, r2.roll, t)
    }
  end
  
  @doc """
  Get forward vector (Z axis) for this rotation.
  """
  def forward(%__MODULE__{} = rotation) do
    %{
      x: :math.sin(rotation.yaw) * :math.cos(rotation.pitch),
      y: :math.sin(rotation.pitch),
      z: :math.cos(rotation.yaw) * :math.cos(rotation.pitch)
    }
  end
  
  @doc """
  Get right vector (X axis) for this rotation.
  """
  def right(%__MODULE__{} = rotation) do
    %{
      x: :math.cos(rotation.yaw),
      y: 0.0,
      z: -:math.sin(rotation.yaw)
    }
  end
  
  @doc """
  Get up vector (Y axis) for this rotation.
  """
  def up(%__MODULE__{} = rotation) do
    %{
      x: -:math.sin(rotation.yaw) * :math.sin(rotation.pitch),
      y: :math.cos(rotation.pitch),
      z: -:math.cos(rotation.yaw) * :math.sin(rotation.pitch)
    }
  end
  
  # Private helpers
  
  defp normalize_angle(angle) do
    # Normalize angle to [-π, π]
    angle = :math.fmod(angle, 2 * :math.pi())
    
    cond do
      angle > :math.pi() -> angle - 2 * :math.pi()
      angle < -:math.pi() -> angle + 2 * :math.pi()
      true -> angle
    end
  end
  
  defp lerp_angle(a1, a2, t) do
    # Handle angle wrapping for smooth interpolation
    diff = a2 - a1
    
    diff = cond do
      diff > :math.pi() -> diff - 2 * :math.pi()
      diff < -:math.pi() -> diff + 2 * :math.pi()
      true -> diff
    end
    
    normalize_angle(a1 + diff * t)
  end
  
  defp degrees_to_radians(degrees) do
    degrees * :math.pi() / 180.0
  end
  
  defp radians_to_degrees(radians) do
    radians * 180.0 / :math.pi()
  end
end