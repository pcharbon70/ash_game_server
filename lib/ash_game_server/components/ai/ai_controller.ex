defmodule AshGameServer.Components.AI.AIController do
  @moduledoc """
  AI Controller component for autonomous entity behavior.
  
  Manages AI state, decision making, and behavior execution.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type ai_state :: :idle | :patrol | :chase | :attack | :flee | :dead | atom()
  @type behavior_type :: :passive | :aggressive | :defensive | :neutral
  
  @type t :: %__MODULE__{
    enabled: boolean(),
    state: ai_state(),
    previous_state: ai_state() | nil,
    behavior_type: behavior_type(),
    target_entity: String.t() | nil,
    home_position: map() | nil,
    patrol_points: [map()],
    current_patrol_index: non_neg_integer(),
    state_timer: float(),
    decision_interval: float(),
    last_decision_time: float()
  }
  
  defstruct [
    enabled: true,
    state: :idle,
    previous_state: nil,
    behavior_type: :neutral,
    target_entity: nil,
    home_position: nil,
    patrol_points: [],
    current_patrol_index: 0,
    state_timer: 0.0,
    decision_interval: 1000.0,  # milliseconds
    last_decision_time: 0.0
  ]
  
  @impl true
  def validate(%__MODULE__{} = ai) do
    cond do
      ai.decision_interval <= 0 ->
        {:error, "Decision interval must be positive"}
      
      ai.current_patrol_index < 0 ->
        {:error, "Patrol index cannot be negative"}
      
      ai.state_timer < 0 ->
        {:error, "State timer cannot be negative"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = ai) do
    %{
      enabled: ai.enabled,
      state: ai.state,
      previous_state: ai.previous_state,
      behavior_type: ai.behavior_type,
      target_entity: ai.target_entity,
      home_position: ai.home_position,
      patrol_points: ai.patrol_points,
      current_patrol_index: ai.current_patrol_index,
      state_timer: Float.round(ai.state_timer * 1.0, 1),
      decision_interval: Float.round(ai.decision_interval * 1.0, 1),
      last_decision_time: Float.round(ai.last_decision_time * 1.0, 1)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      enabled: Map.get(data, :enabled, true),
      state: Map.get(data, :state, :idle),
      previous_state: Map.get(data, :previous_state),
      behavior_type: Map.get(data, :behavior_type, :neutral),
      target_entity: Map.get(data, :target_entity),
      home_position: Map.get(data, :home_position),
      patrol_points: Map.get(data, :patrol_points, []),
      current_patrol_index: Map.get(data, :current_patrol_index, 0),
      state_timer: Map.get(data, :state_timer, 0.0) * 1.0,
      decision_interval: Map.get(data, :decision_interval, 1000.0) * 1.0,
      last_decision_time: Map.get(data, :last_decision_time, 0.0) * 1.0
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a new AI controller with behavior type.
  """
  def new(behavior_type \\ :neutral) do
    %__MODULE__{
      behavior_type: behavior_type,
      state: :idle
    }
  end
  
  @doc """
  Change AI state.
  """
  def change_state(%__MODULE__{} = ai, new_state) do
    if ai.state != new_state do
      %__MODULE__{ai |
        previous_state: ai.state,
        state: new_state,
        state_timer: 0.0
      }
    else
      ai
    end
  end
  
  @doc """
  Set target entity for AI to focus on.
  """
  def set_target(%__MODULE__{} = ai, entity_id) do
    %__MODULE__{ai | target_entity: entity_id}
  end
  
  @doc """
  Clear target entity.
  """
  def clear_target(%__MODULE__{} = ai) do
    %__MODULE__{ai | target_entity: nil}
  end
  
  @doc """
  Set patrol route.
  """
  def set_patrol_route(%__MODULE__{} = ai, points) when is_list(points) do
    %__MODULE__{ai |
      patrol_points: points,
      current_patrol_index: 0
    }
  end
  
  @doc """
  Get next patrol point and advance index.
  """
  def next_patrol_point(%__MODULE__{patrol_points: []} = ai), do: {nil, ai}
  def next_patrol_point(%__MODULE__{} = ai) do
    point = Enum.at(ai.patrol_points, ai.current_patrol_index)
    next_index = rem(ai.current_patrol_index + 1, length(ai.patrol_points))
    
    {point, %__MODULE__{ai | current_patrol_index: next_index}}
  end
  
  @doc """
  Update AI timers with delta time.
  """
  def update_timers(%__MODULE__{} = ai, delta_ms) do
    %__MODULE__{ai |
      state_timer: ai.state_timer + delta_ms,
      last_decision_time: ai.last_decision_time + delta_ms
    }
  end
  
  @doc """
  Check if ready for next decision.
  """
  def needs_decision?(%__MODULE__{} = ai) do
    ai.enabled and ai.last_decision_time >= ai.decision_interval
  end
  
  @doc """
  Reset decision timer.
  """
  def reset_decision_timer(%__MODULE__{} = ai) do
    %__MODULE__{ai | last_decision_time: 0.0}
  end
  
  @doc """
  Enable or disable AI.
  """
  def set_enabled(%__MODULE__{} = ai, enabled) when is_boolean(enabled) do
    %__MODULE__{ai | enabled: enabled}
  end
  
  @doc """
  Check if AI is in combat state.
  """
  def in_combat?(%__MODULE__{state: state}) do
    state in [:attack, :chase, :flee]
  end
  
  @doc """
  Set home position for AI to return to.
  """
  def set_home(%__MODULE__{} = ai, position) do
    %__MODULE__{ai | home_position: position}
  end
end