defmodule AshGameServer.ECS.EnhancedStorage do
  @moduledoc """
  Enhanced storage system for components with optimization, indexing, and access patterns.
  
  Builds on the existing ETS storage foundation to provide:
  - Per-component table optimization
  - Automatic indexing based on component metadata
  - Optimized access patterns
  - Memory management and monitoring
  - Storage analytics and profiling
  """
  use GenServer
  
  alias AshGameServer.ECS.ComponentRegistry
  alias AshGameServer.Storage
  
  @type entity_id :: term()
  @type component_name :: atom()
  @type component_data :: map()
  @type index_name :: atom()
  @type index_value :: term()
  
  @storage_stats_table :enhanced_storage_stats
  @index_tables_prefix "enhanced_index_"
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Stores a component with automatic indexing and optimization.
  """
  @spec put_component(entity_id(), component_name(), component_data()) :: 
    :ok | {:error, term()}
  def put_component(entity_id, component_name, data) do
    GenServer.call(__MODULE__, {:put_component, entity_id, component_name, data})
  end
  
  @doc """
  Gets a component with performance tracking.
  """
  @spec get_component(entity_id(), component_name()) :: 
    {:ok, component_data()} | {:error, term()}
  def get_component(entity_id, component_name) do
    start_time = System.monotonic_time()
    result = Storage.get_component(entity_id, component_name)
    track_access(component_name, :read, System.monotonic_time() - start_time)
    result
  end
  
  @doc """
  Updates a component with change tracking.
  """
  @spec update_component(entity_id(), component_name(), component_data()) :: 
    :ok | {:error, term()}
  def update_component(entity_id, component_name, data) do
    GenServer.call(__MODULE__, {:update_component, entity_id, component_name, data})
  end
  
  @doc """
  Removes a component with cleanup.
  """
  @spec remove_component(entity_id(), component_name()) :: :ok | {:error, term()}
  def remove_component(entity_id, component_name) do
    GenServer.call(__MODULE__, {:remove_component, entity_id, component_name})
  end
  
  @doc """
  Queries components by index values.
  """
  @spec query_by_index(component_name(), index_name(), index_value()) :: [entity_id()]
  def query_by_index(component_name, index_name, value) do
    table_name = index_table_name(component_name, index_name)
    
    case :ets.lookup(table_name, value) do
      [{^value, entity_ids}] -> entity_ids
      [] -> []
    end
  end
  
  @doc """
  Gets multiple components efficiently.
  """
  @spec batch_get_components([{entity_id(), component_name()}]) :: 
    [{entity_id(), component_name(), {:ok, component_data()} | {:error, term()}}]
  def batch_get_components(requests) do
    start_time = System.monotonic_time()
    
    results = Enum.map(requests, fn {entity_id, component_name} ->
      result = Storage.get_component(entity_id, component_name)
      {entity_id, component_name, result}
    end)
    
    # Track batch operation
    duration = System.monotonic_time() - start_time
    track_batch_access(length(requests), duration)
    
    results
  end
  
  @doc """
  Gets storage statistics for performance monitoring.
  """
  @spec get_storage_stats() :: map()
  def get_storage_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Gets component-specific statistics.
  """
  @spec get_component_stats(component_name()) :: map()
  def get_component_stats(component_name) do
    case :ets.lookup(@storage_stats_table, component_name) do
      [{^component_name, stats}] -> stats
      [] -> %{read_count: 0, write_count: 0, total_read_time: 0, total_write_time: 0}
    end
  end
  
  @doc """
  Optimizes storage for a specific component type.
  """
  @spec optimize_component_storage(component_name()) :: :ok
  def optimize_component_storage(component_name) do
    GenServer.cast(__MODULE__, {:optimize_storage, component_name})
  end
  
  @doc """
  Creates indexes for a component based on its metadata.
  """
  @spec create_indexes(component_name()) :: :ok
  def create_indexes(component_name) do
    GenServer.cast(__MODULE__, {:create_indexes, component_name})
  end
  
  # Private Functions
  
  defp track_access(component_name, operation, duration) do
    :ets.update_counter(@storage_stats_table, component_name, [
      {2, 1},  # increment operation count
      {if(operation == :read, do: 4, else: 6), duration}  # add to total time
    ], {component_name, 0, 0, 0, 0, 0, 0})
  end
  
  defp track_batch_access(count, duration) do
    :ets.update_counter(@storage_stats_table, :batch_operations, [
      {2, 1},  # increment batch count
      {3, count},  # add to total entities processed
      {4, duration}  # add to total time
    ], {:batch_operations, 0, 0, 0})
  end
  
  defp index_table_name(component_name, index_name) do
    String.to_atom("#{@index_tables_prefix}#{component_name}_#{index_name}")
  end
  
  defp update_indexes(entity_id, component_name, data, old_data \\ nil) do
    case ComponentRegistry.get_component(component_name) do
      {:ok, metadata} ->
        indexes = Map.get(metadata, :indexes, [])
        
        # Remove old index entries
        if old_data do
          remove_index_entries(entity_id, component_name, old_data, indexes)
        end
        
        # Add new index entries
        add_index_entries(entity_id, component_name, data, indexes)
        
      _ -> :ok
    end
  end
  
  defp add_index_entries(entity_id, component_name, data, indexes) do
    Enum.each(indexes, fn index_name ->
      if Map.has_key?(data, index_name) do
        value = Map.get(data, index_name)
        table_name = index_table_name(component_name, index_name)
        
        # Add entity to index
        case :ets.lookup(table_name, value) do
          [{^value, entity_ids}] ->
            updated_ids = [entity_id | entity_ids] |> Enum.uniq()
            :ets.insert(table_name, {value, updated_ids})
          [] ->
            :ets.insert(table_name, {value, [entity_id]})
        end
      end
    end)
  end
  
  defp remove_index_entries(entity_id, component_name, data, indexes) do
    Enum.each(indexes, fn index_name ->
      if Map.has_key?(data, index_name) do
        value = Map.get(data, index_name)
        table_name = index_table_name(component_name, index_name)
        
        # Remove entity from index
        case :ets.lookup(table_name, value) do
          [{^value, entity_ids}] ->
            updated_ids = List.delete(entity_ids, entity_id)
            if updated_ids == [] do
              :ets.delete(table_name, value)
            else
              :ets.insert(table_name, {value, updated_ids})
            end
          [] -> :ok
        end
      end
    end)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Create stats table
    :ets.new(@storage_stats_table, [:named_table, :public, :set])
    
    state = %{
      index_tables: %{},
      optimization_tasks: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:put_component, entity_id, component_name, data}, _from, state) do
    start_time = System.monotonic_time()
    
    # Validate component data
    result = case ComponentRegistry.validate_component(component_name, data) do
      :ok ->
        # Store in base storage
        Storage.add_component(entity_id, component_name, data)
        
        # Update indexes
        update_indexes(entity_id, component_name, data)
        
        :ok
        
      error -> error
    end
    
    # Track timing
    duration = System.monotonic_time() - start_time
    track_access(component_name, :write, duration)
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:update_component, entity_id, component_name, data}, _from, state) do
    start_time = System.monotonic_time()
    
    # Get old data for index cleanup
    old_data = case Storage.get_component(entity_id, component_name) do
      {:ok, data} -> data
      _ -> nil
    end
    
    result = case ComponentRegistry.validate_component(component_name, data) do
      :ok ->
        # Update in base storage (using add_component as update)
        Storage.add_component(entity_id, component_name, data)
        
        # Update indexes
        update_indexes(entity_id, component_name, data, old_data)
        
        :ok
        
      error -> error
    end
    
    duration = System.monotonic_time() - start_time
    track_access(component_name, :write, duration)
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:remove_component, entity_id, component_name}, _from, state) do
    # Get current data for index cleanup
    old_data = case Storage.get_component(entity_id, component_name) do
      {:ok, data} -> data
      _ -> nil
    end
    
    result = Storage.remove_component(entity_id, component_name)
    
    # Clean up indexes
    if old_data do
      case ComponentRegistry.get_component(component_name) do
        {:ok, metadata} ->
          indexes = Map.get(metadata, :indexes, [])
          remove_index_entries(entity_id, component_name, old_data, indexes)
        _ -> :ok
      end
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = :ets.tab2list(@storage_stats_table)
    |> Enum.into(%{})
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:create_indexes, component_name}, state) do
    case ComponentRegistry.get_component(component_name) do
      {:ok, metadata} ->
        indexes = Map.get(metadata, :indexes, [])
        
        # Create ETS tables for each index
        new_tables = Enum.reduce(indexes, state.index_tables, fn index_name, acc ->
          table_name = index_table_name(component_name, index_name)
          
          if not Map.has_key?(acc, table_name) do
            :ets.new(table_name, [:named_table, :public, :bag])
            Map.put(acc, table_name, {component_name, index_name})
          else
            acc
          end
        end)
        
        {:noreply, %{state | index_tables: new_tables}}
        
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast({:optimize_storage, component_name}, state) do
    # Run storage optimization in background
    Task.start(fn ->
      optimize_component_storage_async(component_name)
    end)
    
    {:noreply, state}
  end
  
  defp optimize_component_storage_async(component_name) do
    # Rebuild indexes for better performance
    case ComponentRegistry.get_component(component_name) do
      {:ok, metadata} ->
        indexes = Map.get(metadata, :indexes, [])
        
        # Clear and rebuild indexes
        Enum.each(indexes, fn index_name ->
          table_name = index_table_name(component_name, index_name)
          :ets.delete_all_objects(table_name)
          
          # Rebuild from current data
          # This would involve scanning all entities with this component
          # and rebuilding the index - implementation depends on base storage
        end)
        
      _ -> :ok
    end
  end
end