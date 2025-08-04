defmodule AshGameServer.Components.Network.ReplicationState do
  @moduledoc """
  ReplicationState component for managing network synchronization.
  
  Controls which components are replicated across the network and tracks
  replication status and timing.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    network_id: String.t(),
    owner_client: String.t() | nil,
    replicate_position: boolean(),
    replicate_rotation: boolean(),
    replicate_velocity: boolean(),
    replicate_health: boolean(),
    replicate_animation: boolean(),
    replicate_custom: [atom()],
    update_frequency: float(),
    last_update_tick: integer(),
    update_count: integer(),
    priority: integer(),
    always_relevant: boolean()
  }
  
  defstruct [
    network_id: "",
    owner_client: nil,
    replicate_position: true,
    replicate_rotation: false,
    replicate_velocity: false,
    replicate_health: true,
    replicate_animation: true,
    replicate_custom: [],
    update_frequency: 20.0,  # Hz
    last_update_tick: 0,
    update_count: 0,
    priority: 1,
    always_relevant: false
  ]
  
  @impl true
  def validate(%__MODULE__{} = repl_state) do
    with :ok <- validate_network_id(repl_state),
         :ok <- validate_frequency(repl_state),
         :ok <- validate_priority(repl_state) do
    end
  end
  
  defp validate_network_id(%__MODULE__{network_id: id}) when id == "" do
    {:error, "Network ID cannot be empty"}
  end
  defp validate_network_id(_repl_state), do: :ok
  
  defp validate_frequency(%__MODULE__{update_frequency: freq}) when freq <= 0.0 do
    {:error, "Update frequency must be positive"}
  end
  defp validate_frequency(_repl_state), do: :ok
  
  defp validate_priority(%__MODULE__{priority: priority}) when priority < 0 do
    {:error, "Priority cannot be negative"}
  end
  defp validate_priority(_repl_state), do: :ok
  
  @impl true
  def serialize(%__MODULE__{} = repl_state) do
    %{
      network_id: repl_state.network_id,
      owner_client: repl_state.owner_client,
      replicate_position: repl_state.replicate_position,
      replicate_rotation: repl_state.replicate_rotation,
      replicate_velocity: repl_state.replicate_velocity,
      replicate_health: repl_state.replicate_health,
      replicate_animation: repl_state.replicate_animation,
      replicate_custom: repl_state.replicate_custom,
      update_frequency: Float.round(repl_state.update_frequency * 1.0, 1),
      last_update_tick: repl_state.last_update_tick,
      update_count: repl_state.update_count,
      priority: repl_state.priority,
      always_relevant: repl_state.always_relevant
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      network_id: Map.get(data, :network_id, ""),
      owner_client: Map.get(data, :owner_client),
      replicate_position: Map.get(data, :replicate_position, true),
      replicate_rotation: Map.get(data, :replicate_rotation, false),
      replicate_velocity: Map.get(data, :replicate_velocity, false),
      replicate_health: Map.get(data, :replicate_health, true),
      replicate_animation: Map.get(data, :replicate_animation, true),
      replicate_custom: Map.get(data, :replicate_custom, []),
      update_frequency: max(Map.get(data, :update_frequency, 20.0) * 1.0, 0.1),
      last_update_tick: Map.get(data, :last_update_tick, 0),
      update_count: Map.get(data, :update_count, 0),
      priority: max(Map.get(data, :priority, 1), 0),
      always_relevant: Map.get(data, :always_relevant, false)
    }}
  end
  
  # Helper functions
  
  @doc """
  Create replication state for a player-owned entity.
  """
  def player_owned(network_id, owner_client) do
    %__MODULE__{
      network_id: network_id,
      owner_client: owner_client,
      replicate_position: true,
      replicate_velocity: true,
      replicate_health: true,
      update_frequency: 30.0,
      priority: 3
    }
  end
  
  @doc """
  Create replication state for an NPC entity.
  """
  def npc(network_id) do
    %__MODULE__{
      network_id: network_id,
      owner_client: nil,
      replicate_position: true,
      replicate_health: true,
      replicate_animation: true,
      update_frequency: 15.0,
      priority: 2
    }
  end
  
  @doc """
  Create replication state for a static object.
  """
  def static_object(network_id) do
    %__MODULE__{
      network_id: network_id,
      owner_client: nil,
      replicate_position: false,
      replicate_velocity: false,
      replicate_health: false,
      replicate_animation: false,
      update_frequency: 1.0,
      priority: 1,
      always_relevant: true
    }
  end
  
  @doc """
  Set which components should be replicated.
  """
  def set_replication_flags(%__MODULE__{} = repl_state, opts \\ []) do
    %__MODULE__{repl_state |
      replicate_position: Keyword.get(opts, :position, repl_state.replicate_position),
      replicate_rotation: Keyword.get(opts, :rotation, repl_state.replicate_rotation),
      replicate_velocity: Keyword.get(opts, :velocity, repl_state.replicate_velocity),
      replicate_health: Keyword.get(opts, :health, repl_state.replicate_health),
      replicate_animation: Keyword.get(opts, :animation, repl_state.replicate_animation)
    }
  end
  
  @doc """
  Add custom component to replication list.
  """
  def add_custom_replication(%__MODULE__{} = repl_state, component_type) when is_atom(component_type) do
    if component_type in repl_state.replicate_custom do
      repl_state
    else
      %__MODULE__{repl_state |
        replicate_custom: [component_type | repl_state.replicate_custom]
      }
    end
  end
  
  @doc """
  Remove custom component from replication list.
  """
  def remove_custom_replication(%__MODULE__{} = repl_state, component_type) do
    %__MODULE__{repl_state |
      replicate_custom: List.delete(repl_state.replicate_custom, component_type)
    }
  end
  
  @doc """
  Set update frequency and priority.
  """
  def set_update_properties(%__MODULE__{} = repl_state, frequency, priority \\ nil) do
    %__MODULE__{repl_state |
      update_frequency: max(frequency, 0.1),
      priority: max(priority || repl_state.priority, 0)
    }
  end
  
  @doc """
  Check if entity should be updated based on frequency.
  """
  def should_update?(%__MODULE__{} = repl_state, current_tick) do
    if repl_state.update_frequency <= 0 do
      false
    else
      tick_interval = trunc(60.0 / repl_state.update_frequency)  # Assume 60 TPS
      (current_tick - repl_state.last_update_tick) >= tick_interval
    end
  end
  
  @doc """
  Get list of all components that should be replicated.
  """
  def get_replicated_components(%__MODULE__{} = repl_state) do
    base_components = []
    
    base_components = if repl_state.replicate_position do
      [:position | base_components]
    else
      base_components
    end
    
    base_components = if repl_state.replicate_rotation do
      [:rotation | base_components]
    else
      base_components
    end
    
    base_components = if repl_state.replicate_velocity do
      [:velocity | base_components]
    else
      base_components
    end
    
    base_components = if repl_state.replicate_health do
      [:health | base_components]
    else
      base_components
    end
    
    base_components = if repl_state.replicate_animation do
      [:animation | base_components]
    else
      base_components
    end
    
    base_components ++ repl_state.replicate_custom
  end
  
  @doc """
  Check if entity is owned by a specific client.
  """
  def owned_by?(%__MODULE__{owner_client: owner}, client_id) do
    owner == client_id
  end
  
  @doc """
  Check if entity is server-owned (no client owner).
  """
  def server_owned?(%__MODULE__{owner_client: nil}), do: true
  def server_owned?(_), do: false
  
  @doc """
  Transfer ownership to a different client.
  """
  def transfer_ownership(%__MODULE__{} = repl_state, new_owner) do
    %__MODULE__{repl_state | owner_client: new_owner}
  end
  
  @doc """
  Update replication statistics.
  """
  def record_update(%__MODULE__{} = repl_state, tick) do
    %__MODULE__{repl_state |
      last_update_tick: tick,
      update_count: repl_state.update_count + 1
    }
  end
end