defmodule AshGameServer.Components.Transform do
  @moduledoc """
  Transform module that provides all spatial transformation components.
  
  This module acts as a namespace and provides convenience functions
  for working with transform components together.
  """
  
  alias AshGameServer.Components.Transform.{Position, Rotation, Scale, Velocity}
  
  @doc """
  Create a complete transform with default values.
  """
  def new(opts \\ []) do
    %{
      position: Keyword.get(opts, :position, Position.origin()),
      rotation: Keyword.get(opts, :rotation, Rotation.identity()),
      scale: Keyword.get(opts, :scale, Scale.identity()),
      velocity: Keyword.get(opts, :velocity, Velocity.zero())
    }
  end
  
  @doc """
  Apply velocity to position and rotation over a time delta.
  """
  def apply_velocity(transform, delta_time) when is_number(delta_time) do
    %{position: pos, rotation: rot, velocity: vel} = transform
    
    # Update position based on linear velocity
    new_position = %Position{
      x: pos.x + vel.linear_x * delta_time,
      y: pos.y + vel.linear_y * delta_time,
      z: pos.z + vel.linear_z * delta_time
    }
    
    # Update rotation based on angular velocity
    new_rotation = %Rotation{
      pitch: rot.pitch + vel.angular_x * delta_time,
      yaw: rot.yaw + vel.angular_y * delta_time,
      roll: rot.roll + vel.angular_z * delta_time
    }
    
    %{transform |
      position: new_position,
      rotation: new_rotation
    }
  end
  
  @doc """
  Transform a point from local space to world space.
  """
  def local_to_world(%{position: pos, rotation: rot, scale: scale}, local_point) do
    # Apply scale
    scaled = %{
      x: local_point.x * scale.x,
      y: local_point.y * scale.y,
      z: local_point.z * scale.z
    }
    
    # Apply rotation (simplified for Euler angles)
    # In a real implementation, this would use rotation matrices
    cos_pitch = :math.cos(rot.pitch)
    sin_pitch = :math.sin(rot.pitch)
    cos_yaw = :math.cos(rot.yaw)
    sin_yaw = :math.sin(rot.yaw)
    cos_roll = :math.cos(rot.roll)
    sin_roll = :math.sin(rot.roll)
    
    # Rotate around Z (roll)
    x1 = scaled.x * cos_roll - scaled.y * sin_roll
    y1 = scaled.x * sin_roll + scaled.y * cos_roll
    z1 = scaled.z
    
    # Rotate around X (pitch)
    x2 = x1
    y2 = y1 * cos_pitch - z1 * sin_pitch
    z2 = y1 * sin_pitch + z1 * cos_pitch
    
    # Rotate around Y (yaw)
    x3 = x2 * cos_yaw + z2 * sin_yaw
    y3 = y2
    z3 = -x2 * sin_yaw + z2 * cos_yaw
    
    # Apply translation
    %{
      x: x3 + pos.x,
      y: y3 + pos.y,
      z: z3 + pos.z
    }
  end
  
  @doc """
  Get the forward direction vector for a transform.
  """
  def forward(%{rotation: rot}) do
    Rotation.forward(rot)
  end
  
  @doc """
  Get the right direction vector for a transform.
  """
  def right(%{rotation: rot}) do
    Rotation.right(rot)
  end
  
  @doc """
  Get the up direction vector for a transform.
  """
  def up(%{rotation: rot}) do
    Rotation.up(rot)
  end
  
  @doc """
  Create a transform matrix (4x4) from transform components.
  
  Returns a flat list of 16 values in row-major order.
  """
  def to_matrix(%{position: pos, rotation: rot, scale: scale}) do
    # Calculate rotation matrix elements
    cos_p = :math.cos(rot.pitch)
    sin_p = :math.sin(rot.pitch)
    cos_y = :math.cos(rot.yaw)
    sin_y = :math.sin(rot.yaw)
    cos_r = :math.cos(rot.roll)
    sin_r = :math.sin(rot.roll)
    
    # Combined rotation matrix (yaw * pitch * roll)
    m11 = cos_y * cos_r + sin_y * sin_p * sin_r
    m12 = -cos_y * sin_r + sin_y * sin_p * cos_r
    m13 = sin_y * cos_p
    
    m21 = cos_p * sin_r
    m22 = cos_p * cos_r
    m23 = -sin_p
    
    m31 = -sin_y * cos_r + cos_y * sin_p * sin_r
    m32 = sin_y * sin_r + cos_y * sin_p * cos_r
    m33 = cos_y * cos_p
    
    # Apply scale and create final matrix
    [
      m11 * scale.x, m12 * scale.y, m13 * scale.z, pos.x,
      m21 * scale.x, m22 * scale.y, m23 * scale.z, pos.y,
      m31 * scale.x, m32 * scale.y, m33 * scale.z, pos.z,
      0.0,           0.0,           0.0,           1.0
    ]
  end
  
  @doc """
  Linear interpolation between two transforms.
  """
  def lerp(t1, t2, alpha) when is_number(alpha) do
    %{
      position: Position.lerp(t1.position, t2.position, alpha),
      rotation: Rotation.lerp(t1.rotation, t2.rotation, alpha),
      scale: Scale.lerp(t1.scale, t2.scale, alpha),
      velocity: Velocity.lerp(t1.velocity, t2.velocity, alpha)
    }
  end
  
  @doc """
  Check if a transform has been modified from defaults.
  """
  def modified?(%{position: pos, rotation: rot, scale: scale, velocity: vel}) do
    not (
      pos == Position.origin() and
      rot == Rotation.identity() and
      scale == Scale.identity() and
      Velocity.stopped?(vel)
    )
  end
end