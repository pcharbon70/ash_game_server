defmodule AshGameServer.Components.Transform.Velocity do
  @moduledoc """
  Velocity component for entity movement in 3D space.
  
  Stores linear velocity (units per second) and angular velocity (radians per second).
  Used by movement systems to update entity positions and rotations.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    linear_x: float(),
    linear_y: float(),
    linear_z: float(),
    angular_x: float(),  # Pitch velocity
    angular_y: float(),  # Yaw velocity
    angular_z: float()   # Roll velocity
  }
  
  defstruct [
    linear_x: 0.0,
    linear_y: 0.0,
    linear_z: 0.0,
    angular_x: 0.0,
    angular_y: 0.0,
    angular_z: 0.0
  ]
  
  @impl true
  def validate(%__MODULE__{} = velocity) do
    fields = [:linear_x, :linear_y, :linear_z, :angular_x, :angular_y, :angular_z]
    
    invalid_field = Enum.find(fields, fn field ->
      not is_number(Map.get(velocity, field))
    end)
    
    if invalid_field do
      {:error, "Velocity #{invalid_field} must be a number"}
    else
      :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = velocity) do
    %{
      linear_x: Float.round(velocity.linear_x * 1.0, 3),
      linear_y: Float.round(velocity.linear_y * 1.0, 3),
      linear_z: Float.round(velocity.linear_z * 1.0, 3),
      angular_x: Float.round(velocity.angular_x * 1.0, 4),
      angular_y: Float.round(velocity.angular_y * 1.0, 4),
      angular_z: Float.round(velocity.angular_z * 1.0, 4)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      linear_x: Map.get(data, :linear_x, 0.0) * 1.0,
      linear_y: Map.get(data, :linear_y, 0.0) * 1.0,
      linear_z: Map.get(data, :linear_z, 0.0) * 1.0,
      angular_x: Map.get(data, :angular_x, 0.0) * 1.0,
      angular_y: Map.get(data, :angular_y, 0.0) * 1.0,
      angular_z: Map.get(data, :angular_z, 0.0) * 1.0
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a new velocity with no movement.
  """
  def zero do
    %__MODULE__{}
  end
  
  @doc """
  Create a new velocity with only linear movement.
  """
  def linear(x, y, z \\ 0.0) do
    %__MODULE__{
      linear_x: x * 1.0,
      linear_y: y * 1.0,
      linear_z: z * 1.0
    }
  end
  
  @doc """
  Create a new velocity with only angular movement.
  """
  def angular(pitch, yaw, roll \\ 0.0) do
    %__MODULE__{
      angular_x: pitch * 1.0,
      angular_y: yaw * 1.0,
      angular_z: roll * 1.0
    }
  end
  
  @doc """
  Get the linear speed (magnitude of linear velocity).
  """
  def linear_speed(%__MODULE__{} = velocity) do
    x = velocity.linear_x
    y = velocity.linear_y
    z = velocity.linear_z
    
    :math.sqrt(x * x + y * y + z * z)
  end
  
  @doc """
  Get the angular speed (magnitude of angular velocity).
  """
  def angular_speed(%__MODULE__{} = velocity) do
    x = velocity.angular_x
    y = velocity.angular_y
    z = velocity.angular_z
    
    :math.sqrt(x * x + y * y + z * z)
  end
  
  @doc """
  Add two velocities together.
  """
  def add(%__MODULE__{} = v1, %__MODULE__{} = v2) do
    %__MODULE__{
      linear_x: v1.linear_x + v2.linear_x,
      linear_y: v1.linear_y + v2.linear_y,
      linear_z: v1.linear_z + v2.linear_z,
      angular_x: v1.angular_x + v2.angular_x,
      angular_y: v1.angular_y + v2.angular_y,
      angular_z: v1.angular_z + v2.angular_z
    }
  end
  
  @doc """
  Scale a velocity by a scalar value.
  """
  def scale(%__MODULE__{} = velocity, scalar) when is_number(scalar) do
    %__MODULE__{
      linear_x: velocity.linear_x * scalar,
      linear_y: velocity.linear_y * scalar,
      linear_z: velocity.linear_z * scalar,
      angular_x: velocity.angular_x * scalar,
      angular_y: velocity.angular_y * scalar,
      angular_z: velocity.angular_z * scalar
    }
  end
  
  @doc """
  Apply damping to velocity (reduces over time).
  """
  def damp(%__MODULE__{} = velocity, linear_damping, angular_damping \\ nil) do
    angular_damping = angular_damping || linear_damping
    
    %__MODULE__{
      linear_x: velocity.linear_x * (1.0 - linear_damping),
      linear_y: velocity.linear_y * (1.0 - linear_damping),
      linear_z: velocity.linear_z * (1.0 - linear_damping),
      angular_x: velocity.angular_x * (1.0 - angular_damping),
      angular_y: velocity.angular_y * (1.0 - angular_damping),
      angular_z: velocity.angular_z * (1.0 - angular_damping)
    }
  end
  
  @doc """
  Clamp linear velocity to a maximum speed.
  """
  def clamp_linear(%__MODULE__{} = velocity, max_speed) when is_number(max_speed) and max_speed > 0 do
    current_speed = linear_speed(velocity)
    
    if current_speed > max_speed do
      scale_factor = max_speed / current_speed
      
      %__MODULE__{velocity |
        linear_x: velocity.linear_x * scale_factor,
        linear_y: velocity.linear_y * scale_factor,
        linear_z: velocity.linear_z * scale_factor
      }
    else
      velocity
    end
  end
  
  @doc """
  Clamp angular velocity to a maximum speed.
  """
  def clamp_angular(%__MODULE__{} = velocity, max_speed) when is_number(max_speed) and max_speed > 0 do
    current_speed = angular_speed(velocity)
    
    if current_speed > max_speed do
      scale_factor = max_speed / current_speed
      
      %__MODULE__{velocity |
        angular_x: velocity.angular_x * scale_factor,
        angular_y: velocity.angular_y * scale_factor,
        angular_z: velocity.angular_z * scale_factor
      }
    else
      velocity
    end
  end
  
  @doc """
  Linear interpolation between two velocities.
  """
  def lerp(%__MODULE__{} = v1, %__MODULE__{} = v2, t) when is_number(t) do
    t = max(0.0, min(1.0, t))
    
    %__MODULE__{
      linear_x: v1.linear_x + (v2.linear_x - v1.linear_x) * t,
      linear_y: v1.linear_y + (v2.linear_y - v1.linear_y) * t,
      linear_z: v1.linear_z + (v2.linear_z - v1.linear_z) * t,
      angular_x: v1.angular_x + (v2.angular_x - v1.angular_x) * t,
      angular_y: v1.angular_y + (v2.angular_y - v1.angular_y) * t,
      angular_z: v1.angular_z + (v2.angular_z - v1.angular_z) * t
    }
  end
  
  @doc """
  Check if velocity is effectively zero (within threshold).
  """
  def stopped?(%__MODULE__{} = velocity, threshold \\ 0.001) do
    linear_speed(velocity) < threshold and angular_speed(velocity) < threshold
  end
end