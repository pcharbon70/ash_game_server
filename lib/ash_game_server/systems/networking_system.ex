defmodule AshGameServer.Systems.NetworkingSystem do
  @moduledoc """
  Networking System for handling state synchronization and client communication.
  
  Manages delta compression, lag compensation, prediction, rollback, and
  network state synchronization for multiplayer gameplay.
  """
  
  use AshGameServer.Systems.SystemBehaviour
  
  alias AshGameServer.Components.Network.{NetworkID, ReplicationState, PredictionState}
  alias AshGameServer.Components.Transform.Position
  # alias AshGameServer.Components.Transform.Velocity  # Unused until velocity networking is implemented
  # alias AshGameServer.Components.Gameplay.Health     # Unused until health networking is implemented
  
  @type network_state :: %{
    tick_rate: integer(),
    current_tick: integer(),
    tick_accumulator: float(),
    snapshot_buffer: %{integer() => map()},
    max_snapshots: integer(),
    delta_compression: boolean(),
    lag_compensation_ms: float(),
    prediction_enabled: boolean(),
    rollback_enabled: boolean(),
    connected_clients: %{String.t() => client_info()},
    bandwidth_monitor: map()
  }
  
  @type client_info :: %{
    client_id: String.t(),
    last_ack_tick: integer(),
    round_trip_time: float(),
    packet_loss: float(),
    bandwidth_usage: integer(),
    prediction_errors: integer()
  }
  
  @type network_message :: %{
    type: atom(),
    tick: integer(),
    entities: [entity_update()],
    timestamp: integer(),
    client_id: String.t() | nil
  }
  
  @type entity_update :: %{
    entity_id: String.t(),
    components: %{atom() => any()},
    delta: boolean()
  }
  
  @impl true
  def init(_opts) do
    {:ok, %{
      tick_rate: 60,  # Server ticks per second
      current_tick: 0,
      tick_accumulator: 0.0,
      snapshot_buffer: %{},
      max_snapshots: 300,  # 5 seconds at 60fps
      delta_compression: true,
      lag_compensation_ms: 100.0,
      prediction_enabled: true,
      rollback_enabled: true,
      connected_clients: %{},
      bandwidth_monitor: %{
        total_bytes_sent: 0,
        total_bytes_received: 0,
        messages_sent: 0,
        messages_received: 0
      }
    }}
  end
  
  @impl true
  def priority, do: 10  # Run early to capture state
  
  @impl true
  def required_components, do: [NetworkID]
  
  @impl true
  def execute(entities, state) do
    # Process each networked entity
    Enum.each(entities, fn {entity_id, components} ->
      process_entity(entity_id, components, state)
    end)
    
    # Update tick timing
    updated_state = update_tick_timing(state, 16.67)  # ~60fps
    
    # Create network snapshot if tick boundary reached
    final_state = if tick_boundary_reached?(updated_state) do
      updated_state
      |> advance_tick()
      |> create_network_snapshot()
      |> process_client_updates()
      |> cleanup_old_snapshots()
    else
      updated_state
    end
    
    {:ok, final_state}
  end
  
  @impl true
  def process_entity(entity_id, components, state) do
    case get_component(entity_id, NetworkID) do
      {:ok, network_id} ->
        # Update replication state for networked entities
        update_entity_replication(entity_id, network_id, state)
        
        # Handle prediction if enabled
        if state.prediction_enabled do
          process_client_prediction(entity_id, network_id, state)
        end
      
      _ -> :skip
    end
    
    {:ok, components}
  end
  
  # Public API for networking
  
  @doc """
  Register a new client connection.
  """
  def register_client(state, client_id) do
    client_info = %{
      client_id: client_id,
      last_ack_tick: state.current_tick,
      round_trip_time: 0.0,
      packet_loss: 0.0,
      bandwidth_usage: 0,
      prediction_errors: 0
    }
    
    %{state | connected_clients: Map.put(state.connected_clients, client_id, client_info)}
  end
  
  @doc """
  Remove a client connection.
  """
  def unregister_client(state, client_id) do
    %{state | connected_clients: Map.delete(state.connected_clients, client_id)}
  end
  
  @doc """
  Process incoming client input.
  """
  def process_client_input(state, client_id, input_data) do
    # Handle client input with lag compensation
    compensated_tick = calculate_lag_compensated_tick(state, client_id)
    
    # Apply input to appropriate game state
    if state.rollback_enabled and compensated_tick < state.current_tick do
      # Rollback and replay if needed
      rollback_and_replay(state, compensated_tick, client_id, input_data)
    else
      # Apply input directly
      apply_client_input(client_id, input_data, compensated_tick)
    end
    
    state
  end
  
  @doc """
  Send state update to all clients.
  """
  def broadcast_state_update(state, update_data) do
    # Send to all connected clients
    Enum.each(state.connected_clients, fn {client_id, _client_info} ->
      send_to_client(client_id, update_data, state.current_tick)
    end)
    
    # Update bandwidth monitoring
    message_size = calculate_message_size(update_data)
    update_bandwidth_stats(state, message_size * map_size(state.connected_clients))
  end
  
  @doc """
  Send state update to specific client.
  """
  def send_to_client(client_id, update_data, tick) do
    message = %{
      type: :state_update,
      tick: tick,
      entities: update_data,
      timestamp: System.monotonic_time(),
      client_id: nil
    }
    
    # This would integrate with actual networking layer
    # For now, we'll use PubSub
    Phoenix.PubSub.broadcast(
      AshGameServer.PubSub,
      "client:#{client_id}",
      {:network_update, message}
    )
  end
  
  # Private functions
  
  defp update_tick_timing(state, delta_ms) do
    new_accumulator = state.tick_accumulator + delta_ms
    
    %{state | tick_accumulator: new_accumulator}
  end
  
  defp tick_boundary_reached?(%{tick_accumulator: acc, tick_rate: rate}) do
    tick_interval = 1000.0 / rate
    acc >= tick_interval
  end
  
  defp advance_tick(state) do
    tick_interval = 1000.0 / state.tick_rate
    new_accumulator = state.tick_accumulator - tick_interval
    
    %{state |
      current_tick: state.current_tick + 1,
      tick_accumulator: new_accumulator
    }
  end
  
  defp create_network_snapshot(state) do
    # In a real implementation, this would query all networked entities
    # For now, just store an empty snapshot
    updated_buffer = Map.put(state.snapshot_buffer, state.current_tick, %{})
    
    %{state | snapshot_buffer: updated_buffer}
  end
  
  # TODO: Enable when full entity state capture is needed
  # defp capture_entity_state(entity_id) do
  #   # Capture relevant components for networking
  #   components = %{}
  #   
  #   # Position
  #   components = case get_component(entity_id, Position) do
  #     {:ok, pos} -> Map.put(components, :position, pos)
  #     _ -> components
  #   end
  #   
  #   # Velocity
  #   components = case get_component(entity_id, Velocity) do
  #     {:ok, vel} -> Map.put(components, :velocity, vel)
  #     _ -> components
  #   end
  #   
  #   # Health
  #   components = case get_component(entity_id, Health) do
  #     {:ok, health} -> Map.put(components, :health, health)
  #     _ -> components
  #   end
  #   
  #   # Network-specific data
  #   components = case get_component(entity_id, ReplicationState) do
  #     {:ok, repl} -> Map.put(components, :replication, repl)
  #     _ -> components
  #   end
  #   
  #   %{
  #     entity_id: entity_id,
  #     components: components,
  #     timestamp: System.monotonic_time()
  #   }
  # end
  
  defp process_client_updates(state) do
    # Create delta updates for each client
    Enum.reduce(state.connected_clients, state, fn {client_id, client_info}, acc_state ->
      # Generate update based on client's last acknowledged tick
      update_data = generate_client_update(acc_state, client_info)
      
      # Send update to client
      send_to_client(client_id, update_data, state.current_tick)
      
      acc_state
    end)
  end
  
  defp generate_client_update(state, client_info) do
    current_snapshot = Map.get(state.snapshot_buffer, state.current_tick, %{})
    
    if state.delta_compression and client_info.last_ack_tick > 0 do
      # Generate delta from last acknowledged state
      last_snapshot = Map.get(state.snapshot_buffer, client_info.last_ack_tick, %{})
      generate_delta_update(current_snapshot, last_snapshot)
    else
      # Send full snapshot
      Map.values(current_snapshot)
    end
  end
  
  defp generate_delta_update(current_snapshot, last_snapshot) do
    # Compare snapshots and generate delta
    Enum.reduce(current_snapshot, [], fn {entity_id, current_data}, acc ->
      case Map.get(last_snapshot, entity_id) do
        nil ->
          create_new_entity_update(entity_id, current_data, acc)
        
        last_data ->
          create_delta_entity_update(entity_id, current_data, last_data, acc)
      end
    end)
  end
  
  defp create_new_entity_update(entity_id, current_data, acc) do
    # New entity
    [%{entity_id: entity_id, components: current_data.components, delta: false} | acc]
  end
  
  defp create_delta_entity_update(entity_id, current_data, last_data, acc) do
    # Check for changes
    delta_components = find_component_changes(current_data.components, last_data.components)
    
    case map_size(delta_components) do
      0 -> acc
      _ -> [%{entity_id: entity_id, components: delta_components, delta: true} | acc]
    end
  end
  
  defp find_component_changes(current_components, last_components) do
    Enum.reduce(current_components, %{}, fn {component_type, current_value}, acc ->
      case Map.get(last_components, component_type) do
        ^current_value ->
          # No change
          acc
        
        _ ->
          # Changed or new
          Map.put(acc, component_type, current_value)
      end
    end)
  end
  
  defp cleanup_old_snapshots(state) do
    # Remove snapshots older than max_snapshots
    oldest_tick = state.current_tick - state.max_snapshots
    
    updated_buffer = Map.filter(state.snapshot_buffer, fn {tick, _snapshot} ->
      tick > oldest_tick
    end)
    
    %{state | snapshot_buffer: updated_buffer}
  end
  
  defp update_entity_replication(entity_id, network_id, _state) do
    case get_component(entity_id, ReplicationState) do
      {:ok, repl_state} ->
        # Update replication flags and timing
        updated_repl = %ReplicationState{repl_state |
          last_update_tick: System.monotonic_time(),
          update_count: repl_state.update_count + 1
        }
        
        update_component(entity_id, ReplicationState, updated_repl)
      
      _ ->
        # Create new replication state
        new_repl = %ReplicationState{
          network_id: network_id.id,
          owner_client: network_id.owner_client,
          replicate_position: true,
          replicate_rotation: true,
          replicate_velocity: true,
          last_update_tick: System.monotonic_time(),
          update_count: 1
        }
        
        update_component(entity_id, ReplicationState, new_repl)
    end
  end
  
  defp process_client_prediction(entity_id, network_id, state) do
    # Handle client-side prediction reconciliation
    case get_component(entity_id, PredictionState) do
      {:ok, pred_state} ->
        # Check for prediction errors
        check_prediction_accuracy(entity_id, pred_state, state)
      
      _ ->
        # Initialize prediction state if needed
        if network_id.owner_client do
          init_prediction_state(entity_id, network_id)
        end
    end
  end
  
  defp check_prediction_accuracy(entity_id, pred_state, state) do
    with {:ok, auth_pos} <- get_component(entity_id, Position),
         pred_pos when pred_pos != nil <- pred_state.predicted_position do
      
      error = Position.distance(auth_pos, pred_pos)
      
      if error > 1.0 do
        handle_prediction_correction(entity_id, auth_pos, pred_state, state)
      end
    else
      _ -> :ok
    end
  end
  
  defp handle_prediction_correction(entity_id, auth_pos, pred_state, state) do
    # Send correction to client
    send_prediction_correction(entity_id, auth_pos, state.current_tick)
    
    # Update prediction state
    updated_pred = %PredictionState{pred_state |
      prediction_errors: pred_state.prediction_errors + 1,
      last_correction_tick: state.current_tick
    }
    
    update_component(entity_id, PredictionState, updated_pred)
  end
  
  defp init_prediction_state(entity_id, network_id) do
    pred_state = %PredictionState{
      network_id: network_id.id,
      predicted_position: nil,
      predicted_velocity: nil,
      prediction_errors: 0,
      last_correction_tick: 0
    }
    
    update_component(entity_id, PredictionState, pred_state)
  end
  
  defp calculate_lag_compensated_tick(state, client_id) do
    case Map.get(state.connected_clients, client_id) do
      nil -> state.current_tick
      client_info ->
        # Calculate tick based on RTT
        lag_ticks = trunc((client_info.round_trip_time * 0.5) * state.tick_rate / 1000.0)
        max(0, state.current_tick - lag_ticks)
    end
  end
  
  defp rollback_and_replay(state, target_tick, client_id, input_data) do
    # This is a simplified rollback implementation
    # In a full implementation, this would:
    # 1. Restore game state to target_tick
    # 2. Apply the client input
    # 3. Re-simulate to current_tick
    
    # For now, just apply input with warning
    IO.puts("Rollback needed: tick #{target_tick}, current #{state.current_tick}")
    apply_client_input(client_id, input_data, target_tick)
  end
  
  defp apply_client_input(client_id, input_data, _tick) do
    # Apply client input to owned entities
    # This would integrate with input system
    Phoenix.PubSub.broadcast(
      AshGameServer.PubSub,
      "client_input",
      {:client_input, client_id, input_data}
    )
  end
  
  defp send_prediction_correction(entity_id, correct_position, tick) do
    correction = %{
      type: :prediction_correction,
      entity_id: entity_id,
      correct_position: correct_position,
      tick: tick
    }
    
    # Broadcast correction
    Phoenix.PubSub.broadcast(
      AshGameServer.PubSub,
      "predictions",
      {:correction, correction}
    )
  end
  
  defp calculate_message_size(data) do
    # Rough estimate of serialized message size
    :erlang.byte_size(:erlang.term_to_binary(data))
  end
  
  defp update_bandwidth_stats(state, bytes_sent) do
    updated_monitor = %{state.bandwidth_monitor |
      total_bytes_sent: state.bandwidth_monitor.total_bytes_sent + bytes_sent,
      messages_sent: state.bandwidth_monitor.messages_sent + 1
    }
    
    %{state | bandwidth_monitor: updated_monitor}
  end
  
  # Component access helpers
  defp get_component(entity_id, component_type) do
    case AshGameServer.Storage.ComponentStorage.get(component_type, entity_id) do
      {:ok, component} -> {:ok, component}
      _ -> {:error, :not_found}
    end
  end
  
  defp update_component(entity_id, component_type, component) do
    AshGameServer.Storage.ComponentStorage.put(component_type, entity_id, component)
  end
  
  # Public API for configuration
  
  @doc """
  Set network tick rate.
  """
  def set_tick_rate(state, tick_rate) when tick_rate > 0 and tick_rate <= 120 do
    %{state | tick_rate: tick_rate}
  end
  
  @doc """
  Enable or disable delta compression.
  """
  def set_delta_compression(state, enabled) when is_boolean(enabled) do
    %{state | delta_compression: enabled}
  end
  
  @doc """
  Set lag compensation time.
  """
  def set_lag_compensation(state, ms) when ms >= 0 do
    %{state | lag_compensation_ms: ms}
  end
  
  @doc """
  Enable or disable client prediction.
  """
  def set_prediction_enabled(state, enabled) when is_boolean(enabled) do
    %{state | prediction_enabled: enabled}
  end
  
  @doc """
  Get current bandwidth statistics.
  """
  def get_bandwidth_stats(state) do
    state.bandwidth_monitor
  end
  
  @doc """
  Get client connection information.
  """
  def get_client_info(state, client_id) do
    Map.get(state.connected_clients, client_id)
  end
  
  @doc """
  Update client round trip time.
  """
  def update_client_rtt(state, client_id, rtt_ms) do
    case Map.get(state.connected_clients, client_id) do
      nil -> state
      client_info ->
        updated_client = %{client_info | round_trip_time: rtt_ms}
        updated_clients = Map.put(state.connected_clients, client_id, updated_client)
        %{state | connected_clients: updated_clients}
    end
  end
end