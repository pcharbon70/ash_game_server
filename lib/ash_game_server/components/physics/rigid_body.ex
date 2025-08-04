defmodule AshGameServer.Components.Physics.RigidBody do
  @moduledoc """
  RigidBody component for physics simulation.
  
  Controls mass, drag, gravity, and physics constraints for entities.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    mass: float(),
    drag: float(),
    angular_drag: float(),
    use_gravity: boolean(),
    is_kinematic: boolean(),
    freeze_rotation_x: boolean(),
    freeze_rotation_y: boolean(),
    freeze_rotation_z: boolean(),
    freeze_position_x: boolean(),
    freeze_position_y: boolean(),
    freeze_position_z: boolean()
  }
  
  defstruct [
    mass: 1.0,
    drag: 0.0,
    angular_drag: 0.05,
    use_gravity: true,
    is_kinematic: false,
    freeze_rotation_x: false,
    freeze_rotation_y: false,
    freeze_rotation_z: false,
    freeze_position_x: false,
    freeze_position_y: false,
    freeze_position_z: false
  ]
  
  @impl true
  def validate(%__MODULE__{} = rigid_body) do
    with :ok <- validate_mass(rigid_body),
         :ok <- validate_drag(rigid_body) do
    end
  end
  
  defp validate_mass(%__MODULE__{mass: mass}) when mass <= 0.0 do
    {:error, "Mass must be positive"}
  end
  defp validate_mass(_rigid_body), do: :ok
  
  defp validate_drag(%__MODULE__{drag: drag, angular_drag: angular_drag}) do
    cond do
      drag < 0.0 or drag > 1.0 ->
        {:error, "Drag must be between 0.0 and 1.0"}
      angular_drag < 0.0 or angular_drag > 1.0 ->
        {:error, "Angular drag must be between 0.0 and 1.0"}
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = rigid_body) do
    %{
      mass: Float.round(rigid_body.mass * 1.0, 3),
      drag: Float.round(rigid_body.drag * 1.0, 3),
      angular_drag: Float.round(rigid_body.angular_drag * 1.0, 3),
      use_gravity: rigid_body.use_gravity,
      is_kinematic: rigid_body.is_kinematic,
      freeze_rotation_x: rigid_body.freeze_rotation_x,
      freeze_rotation_y: rigid_body.freeze_rotation_y,
      freeze_rotation_z: rigid_body.freeze_rotation_z,
      freeze_position_x: rigid_body.freeze_position_x,
      freeze_position_y: rigid_body.freeze_position_y,
      freeze_position_z: rigid_body.freeze_position_z
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      mass: max(Map.get(data, :mass, 1.0) * 1.0, 0.001),
      drag: clamp(Map.get(data, :drag, 0.0), 0.0, 1.0),
      angular_drag: clamp(Map.get(data, :angular_drag, 0.05), 0.0, 1.0),
      use_gravity: Map.get(data, :use_gravity, true),
      is_kinematic: Map.get(data, :is_kinematic, false),
      freeze_rotation_x: Map.get(data, :freeze_rotation_x, false),
      freeze_rotation_y: Map.get(data, :freeze_rotation_y, false),
      freeze_rotation_z: Map.get(data, :freeze_rotation_z, false),
      freeze_position_x: Map.get(data, :freeze_position_x, false),
      freeze_position_y: Map.get(data, :freeze_position_y, false),
      freeze_position_z: Map.get(data, :freeze_position_z, false)
    }}
  end
  
  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
  defp clamp(_value, _min, max), do: max
  
  # Helper functions
  
  @doc """
  Create a static rigid body (no movement).
  """
  def static do
    %__MODULE__{
      mass: Float.max_finite(),
      is_kinematic: true,
      use_gravity: false
    }
  end
  
  @doc """
  Create a kinematic rigid body (controlled movement).
  """
  def kinematic(mass \\ 1.0) do
    %__MODULE__{
      mass: mass,
      is_kinematic: true,
      use_gravity: false
    }
  end
  
  @doc """
  Create a dynamic rigid body (physics-driven).
  """
  def dynamic(mass \\ 1.0) do
    %__MODULE__{
      mass: mass,
      is_kinematic: false,
      use_gravity: true
    }
  end
  
  @doc """
  Set mass and automatically adjust for static bodies.
  """
  def set_mass(%__MODULE__{} = rigid_body, mass) when mass > 0.0 do
    %__MODULE__{rigid_body | mass: mass}
  end
  
  @doc """
  Set drag values.
  """
  def set_drag(%__MODULE__{} = rigid_body, drag, angular_drag \\ nil) do
    %__MODULE__{rigid_body |
      drag: clamp(drag, 0.0, 1.0),
      angular_drag: clamp(angular_drag || rigid_body.angular_drag, 0.0, 1.0)
    }
  end
  
  @doc """
  Freeze specific axes of movement.
  """
  def freeze_position(%__MODULE__{} = rigid_body, x \\ false, y \\ false, z \\ false) do
    %__MODULE__{rigid_body |
      freeze_position_x: x,
      freeze_position_y: y,
      freeze_position_z: z
    }
  end
  
  @doc """
  Freeze specific axes of rotation.
  """
  def freeze_rotation(%__MODULE__{} = rigid_body, x \\ false, y \\ false, z \\ false) do
    %__MODULE__{rigid_body |
      freeze_rotation_x: x,
      freeze_rotation_y: y,
      freeze_rotation_z: z
    }
  end
end