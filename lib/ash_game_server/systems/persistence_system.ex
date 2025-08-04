defmodule AshGameServer.Systems.PersistenceSystem do
  @moduledoc """
  Persistence System for handling save/load operations and data versioning.
  
  Manages entity serialization, database persistence, migration handling,
  backup creation, and data recovery operations.
  """
  
  use AshGameServer.Systems.SystemBehaviour
  
  alias AshGameServer.Components.Gameplay.{Health, Combat}
  alias AshGameServer.Components.Transform.{Position, Velocity}
  alias AshGameServer.Components.Network.{NetworkID, ReplicationState}
  alias AshGameServer.Storage.{ComponentStorage, PersistenceBridge}
  
  @type persistence_state :: %{
    auto_save_enabled: boolean(),
    auto_save_interval: float(),
    last_auto_save: integer(),
    save_in_progress: boolean(),
    load_in_progress: boolean(),
    version: String.t(),
    backup_retention: integer(),
    compression_enabled: boolean(),
    migration_handlers: %{String.t() => function()},
    save_statistics: save_stats()
  }
  
  @type save_stats :: %{
    total_saves: integer(),
    total_loads: integer(),
    last_save_duration: float(),
    last_load_duration: float(),
    average_save_size: integer(),
    failed_operations: integer()
  }
  
  @type save_request :: %{
    type: :full | :incremental | :backup,
    target: :database | :file | :memory,
    include_components: [atom()],
    exclude_entities: [String.t()],
    metadata: map()
  }
  
  @type load_request :: %{
    source: :database | :file | :memory,
    version: String.t() | nil,
    filter: map(),
    restore_mode: :replace | :merge | :selective
  }
  
  @impl true
  def init(_opts) do
    {:ok, %{
      auto_save_enabled: true,
      auto_save_interval: 300_000.0,  # 5 minutes in milliseconds
      last_auto_save: System.monotonic_time(),
      save_in_progress: false,
      load_in_progress: false,
      version: "1.0.0",
      backup_retention: 10,
      compression_enabled: true,
      migration_handlers: %{},
      save_statistics: %{
        total_saves: 0,
        total_loads: 0,
        last_save_duration: 0.0,
        last_load_duration: 0.0,
        average_save_size: 0,
        failed_operations: 0
      }
    }}
  end
  
  @impl true
  def priority, do: 5  # Run late to capture final state
  
  @impl true
  def required_components, do: []  # Persistence system can work with any components
  
  @impl true
  def execute(entities, state) do
    # Process entities if needed (persistence system usually doesn't process individual entities)
    _processed_entities = entities
    
    # Check for auto-save
    updated_state = if should_auto_save?(state) do
      perform_auto_save(state)
    else
      state
    end
    
    # Process any pending save/load operations
    process_pending_operations(updated_state)
  end
  
  @impl true
  def process_entity(_entity_id, components, _state) do
    # This system doesn't process individual entities during normal execution
    # Entity processing happens during save/load operations
    {:ok, components}
  end
  
  # Public API for persistence operations
  
  @doc """
  Save current game state to database.
  """
  def save_game_state(state, save_request \\ %{}) do
    if state.save_in_progress do
      {:error, :save_in_progress}
    else
      request = Map.merge(%{
        type: :full,
        target: :database,
        include_components: [:all],
        exclude_entities: [],
        metadata: %{}
      }, save_request)
      
      execute_save_operation(state, request)
    end
  end
  
  @doc """
  Load game state from database.
  """
  def load_game_state(state, load_request \\ %{}) do
    if state.load_in_progress do
      {:error, :load_in_progress}
    else
      request = Map.merge(%{
        source: :database,
        version: nil,
        filter: %{},
        restore_mode: :replace
      }, load_request)
      
      execute_load_operation(state, request)
    end
  end
  
  @doc """
  Create incremental save (only changed entities).
  """
  def save_incremental(state, since_timestamp \\ nil) do
    timestamp = since_timestamp || state.last_auto_save
    
    save_request = %{
      type: :incremental,
      target: :database,
      metadata: %{since_timestamp: timestamp}
    }
    
    save_game_state(state, save_request)
  end
  
  @doc """
  Create backup of current state.
  """
  def create_backup(state, backup_name \\ nil) do
    name = backup_name || "backup_#{System.system_time(:second)}"
    
    save_request = %{
      type: :backup,
      target: :file,
      metadata: %{backup_name: name, created_at: System.system_time()}
    }
    
    save_game_state(state, save_request)
  end
  
  @doc """
  Restore from backup.
  """
  def restore_backup(state, backup_name) do
    load_request = %{
      source: :file,
      filter: %{backup_name: backup_name},
      restore_mode: :replace
    }
    
    load_game_state(state, load_request)
  end
  
  # Private functions
  
  defp should_auto_save?(state) do
    if state.auto_save_enabled and not state.save_in_progress do
      current_time = System.monotonic_time()
      elapsed = (current_time - state.last_auto_save) / 1_000_000  # Convert to milliseconds
      elapsed >= state.auto_save_interval
    else
      false
    end
  end
  
  defp perform_auto_save(state) do
    case save_game_state(state, %{type: :incremental}) do
      {:ok, updated_state} ->
        %{updated_state | last_auto_save: System.monotonic_time()}
      
      {:error, _reason} ->
        # Log error but continue
        state
    end
  end
  
  defp process_pending_operations(state) do
    # In a real implementation, this would process async save/load operations
    # For now, we'll just return the state
    {:ok, state}
  end
  
  defp execute_save_operation(state, save_request) do
    start_time = System.monotonic_time()
    
    try do
      # Mark save in progress
      working_state = %{state | save_in_progress: true}
      
      # Collect entities to save
      entities_to_save = collect_entities_for_save(save_request)
      
      # Serialize entity data
      serialized_data = serialize_entities(entities_to_save, save_request)
      
      # Apply compression if enabled
      final_data = if state.compression_enabled do
        compress_data(serialized_data)
      else
        serialized_data
      end
      
      # Write to target
      result = case save_request.target do
        :database -> save_to_database(final_data, save_request)
        :file -> save_to_file(final_data, save_request)
        :memory -> save_to_memory(final_data, save_request)
      end
      
      # Update statistics
      duration = (System.monotonic_time() - start_time) / 1_000_000
      data_size = byte_size(:erlang.term_to_binary(final_data))
      
      updated_stats = %{state.save_statistics |
        total_saves: state.save_statistics.total_saves + 1,
        last_save_duration: duration,
        average_save_size: calculate_average_size(state.save_statistics, data_size)
      }
      
      final_state = %{working_state |
        save_in_progress: false,
        save_statistics: updated_stats
      }
      
      case result do
        :ok -> {:ok, final_state}
        {:error, reason} -> 
          error_stats = %{updated_stats | failed_operations: updated_stats.failed_operations + 1}
          {:error, reason, %{final_state | save_statistics: error_stats}}
      end
      
    rescue
      error ->
        # Handle save errors
        error_stats = %{state.save_statistics | 
          failed_operations: state.save_statistics.failed_operations + 1
        }
        
        final_state = %{state |
          save_in_progress: false,
          save_statistics: error_stats
        }
        
        {:error, error, final_state}
    end
  end
  
  defp execute_load_operation(state, load_request) do
    start_time = System.monotonic_time()
    working_state = %{state | load_in_progress: true}
    
    try do
      with {:ok, raw_data} <- load_data_from_source(load_request),
           {:ok, decompressed_data} <- decompress_if_needed(raw_data, state.compression_enabled),
           {:ok, final_data} <- handle_version_compatibility(decompressed_data, state, load_request) do
        
        restore_entities(final_data, load_request.restore_mode)
        finalize_successful_load(working_state, start_time)
      else
        {:error, reason} ->
          handle_load_error(reason, working_state)
      end
    rescue
      error ->
        handle_load_exception(error, state)
    end
  end
  
  defp load_data_from_source(load_request) do
    case load_request.source do
      :database -> load_from_database(load_request)
      :file -> load_from_file(load_request)
      :memory -> load_from_memory(load_request)
    end
  end
  
  defp decompress_if_needed(data, compression_enabled) do
    decompressed_data = if compression_enabled do
      decompress_data(data)
    else
      data
    end
    {:ok, decompressed_data}
  end
  
  defp handle_version_compatibility(data, state, load_request) do
    case check_version_compatibility(data, state.version) do
      :ok ->
        {:ok, data}
      
      {:error, :version_mismatch, old_version} ->
        attempt_data_migration(data, old_version, state, load_request)
    end
  end
  
  defp attempt_data_migration(data, old_version, state, _load_request) do
    case migrate_data(data, old_version, state.version, state.migration_handlers) do
      {:ok, migrated_data} ->
        {:ok, migrated_data}
      
      {:error, reason} ->
        {:error, {:migration_failed, reason}}
    end
  end
  
  defp finalize_successful_load(working_state, start_time) do
    duration = (System.monotonic_time() - start_time) / 1_000_000
    updated_stats = %{working_state.save_statistics |
      total_loads: working_state.save_statistics.total_loads + 1,
      last_load_duration: duration
    }
    
    final_state = %{working_state |
      load_in_progress: false,
      save_statistics: updated_stats
    }
    
    {:ok, final_state}
  end
  
  defp handle_load_error(reason, working_state) do
    error_stats = %{working_state.save_statistics | 
      failed_operations: working_state.save_statistics.failed_operations + 1
    }
    
    final_state = %{working_state | 
      load_in_progress: false,
      save_statistics: error_stats
    }
    
    {:error, reason, final_state}
  end
  
  defp handle_load_exception(error, state) do
    error_stats = %{state.save_statistics | 
      failed_operations: state.save_statistics.failed_operations + 1
    }
    
    final_state = %{state |
      load_in_progress: false,
      save_statistics: error_stats
    }
    
    {:error, error, final_state}
  end
  
  defp collect_entities_for_save(_save_request) do
    # In a real implementation, this would query all entities with specified components
    # For now, return empty list
    []
  end
  
  defp serialize_entities(entities, save_request) do
    entity_data = Enum.map(entities, fn entity_id ->
      components = collect_entity_components(entity_id, save_request.include_components)
      
      %{
        entity_id: entity_id,
        components: components,
        serialized_at: System.system_time()
      }
    end)
    
    %{
      version: "1.0.0",
      type: save_request.type,
      entities: entity_data,
      metadata: save_request.metadata,
      created_at: System.system_time()
    }
  end
  
  defp collect_entity_components(entity_id, include_components) do
    component_types = if include_components == [:all] do
      # Get all component types for this entity
      get_entity_component_types(entity_id)
    else
      include_components
    end
    
    Enum.reduce(component_types, %{}, fn component_type, acc ->
      case ComponentStorage.get(component_type, entity_id) do
        {:ok, component} ->
          serialized = component_type.serialize(component)
          Map.put(acc, component_type, serialized)
        
        _ -> acc
      end
    end)
  end
  
  defp get_entity_component_types(entity_id) do
    # This would query the component storage to find all components for an entity
    # For now, return common component types
    [Position, Velocity, Health, Combat, NetworkID, ReplicationState]
    |> Enum.filter(fn component_type ->
      case ComponentStorage.get(component_type, entity_id) do
        {:ok, _} -> true
        _ -> false
      end
    end)
  end
  
  defp compress_data(data) do
    compressed = :zlib.compress(:erlang.term_to_binary(data))
    %{compressed: true, data: compressed}
  end
  
  defp decompress_data(%{compressed: true, data: compressed_data}) do
    decompressed = :zlib.uncompress(compressed_data)
    :erlang.binary_to_term(decompressed)
  end
  defp decompress_data(data), do: data
  
  defp save_to_database(data, save_request) do
    # Use PersistenceBridge to save to Ash resources
    case PersistenceBridge.save_snapshot(data, save_request.metadata) do
      {:ok, _snapshot_id} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp save_to_file(data, save_request) do
    filename = case save_request.metadata do
      %{backup_name: name} -> "#{name}.save"
      _ -> "game_save_#{System.system_time()}.save"
    end
    
    filepath = Path.join("saves", filename)
    File.mkdir_p!("saves")
    
    case File.write(filepath, :erlang.term_to_binary(data)) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp save_to_memory(data, _save_request) do
    # Store in ETS or process state for temporary saves
    :ets.insert(:game_saves, {:memory_save, data})
    :ok
  end
  
  defp load_from_database(load_request) do
    # Use PersistenceBridge to load from Ash resources
    filter = Map.get(load_request, :filter, %{})
    PersistenceBridge.load_snapshot(filter)
  end
  
  defp load_from_file(load_request) do
    filename = case load_request.filter do
      %{backup_name: name} -> "#{name}.save"
      _ -> "latest.save"
    end
    
    filepath = Path.join("saves", filename)
    
    case File.read(filepath) do
      {:ok, binary_data} ->
        data = :erlang.binary_to_term(binary_data)
        {:ok, data}
      
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp load_from_memory(_load_request) do
    case :ets.lookup(:game_saves, :memory_save) do
      [{:memory_save, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end
  
  defp check_version_compatibility(data, current_version) do
    case Map.get(data, :version) do
      ^current_version -> :ok
      nil -> {:error, :version_mismatch, "unknown"}
      old_version -> {:error, :version_mismatch, old_version}
    end
  end
  
  defp migrate_data(data, old_version, new_version, migration_handlers) do
    # Apply migration handlers to upgrade data format
    migration_key = "#{old_version}_to_#{new_version}"
    
    case Map.get(migration_handlers, migration_key) do
      nil -> {:error, :no_migration_handler}
      handler when is_function(handler) ->
        try do
          migrated_data = handler.(data)
          {:ok, %{migrated_data | version: new_version}}
        rescue
          error -> {:error, {:migration_error, error}}
        end
    end
  end
  
  defp restore_entities(data, restore_mode) do
    entities = Map.get(data, :entities, [])
    
    case restore_mode do
      :replace ->
        # Clear existing entities and restore from save
        clear_all_entities()
        create_entities_from_data(entities)
      
      :merge ->
        # Merge with existing entities
        merge_entities_from_data(entities)
      
      :selective ->
        # Only restore specific entities (would need additional criteria)
        selective_restore_entities(entities)
    end
  end
  
  defp clear_all_entities() do
    # This would clear all entity data from component storage
    # For now, just log the operation
    IO.puts("Clearing all entities for restore")
  end
  
  defp create_entities_from_data(entities) do
    Enum.each(entities, &create_entity_from_data/1)
  end
  
  defp create_entity_from_data(entity_data) do
    entity_id = entity_data.entity_id
    
    Enum.each(entity_data.components, fn {component_type, serialized_component} ->
      deserialize_and_store_component(component_type, entity_id, serialized_component)
    end)
  end
  
  defp deserialize_and_store_component(component_type, entity_id, serialized_component) do
    case component_type.deserialize(serialized_component) do
      {:ok, component} ->
        ComponentStorage.put(component_type, entity_id, component)
      
      {:error, reason} ->
        IO.warn("Failed to deserialize component #{component_type} for entity #{entity_id}: #{inspect(reason)}")
    end
  end
  
  defp merge_entities_from_data(entities) do
    # Merge entities with existing data, preferring loaded data
    Enum.each(entities, &merge_entity_from_data/1)
  end
  
  defp merge_entity_from_data(entity_data) do
    entity_id = entity_data.entity_id
    
    Enum.each(entity_data.components, fn {component_type, serialized_component} ->
      merge_component_from_data(component_type, entity_id, serialized_component)
    end)
  end
  
  defp merge_component_from_data(component_type, entity_id, serialized_component) do
    case component_type.deserialize(serialized_component) do
      {:ok, component} ->
        # Always overwrite with loaded data in merge mode
        ComponentStorage.put(component_type, entity_id, component)
      
      {:error, reason} ->
        IO.warn("Failed to merge component #{component_type} for entity #{entity_id}: #{inspect(reason)}")
    end
  end
  
  defp selective_restore_entities(entities) do
    # For now, same as merge - would need additional logic for selection criteria
    merge_entities_from_data(entities)
  end
  
  defp calculate_average_size(stats, new_size) do
    if stats.total_saves == 0 do
      new_size
    else
      total_size = stats.average_save_size * stats.total_saves + new_size
      trunc(total_size / (stats.total_saves + 1))
    end
  end
  
  # Public API for configuration
  
  @doc """
  Enable or disable auto-save.
  """
  def set_auto_save(state, enabled, interval \\ nil) do
    %{state |
      auto_save_enabled: enabled,
      auto_save_interval: interval || state.auto_save_interval
    }
  end
  
  @doc """
  Set data compression setting.
  """
  def set_compression(state, enabled) when is_boolean(enabled) do
    %{state | compression_enabled: enabled}
  end
  
  @doc """
  Add a migration handler for version upgrades.
  """
  def add_migration_handler(state, from_version, to_version, handler) when is_function(handler) do
    key = "#{from_version}_to_#{to_version}"
    updated_handlers = Map.put(state.migration_handlers, key, handler)
    %{state | migration_handlers: updated_handlers}
  end
  
  @doc """
  Get persistence statistics.
  """
  def get_statistics(state) do
    state.save_statistics
  end
  
  @doc """
  Set backup retention policy.
  """
  def set_backup_retention(state, count) when count > 0 do
    %{state | backup_retention: count}
  end
end