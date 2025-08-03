defmodule AshGameServer.Storage.ComponentStorage do
  @moduledoc """
  High-performance component storage using ETS tables.
  
  This module provides the primary interface for storing and retrieving
  ECS components with sub-millisecond access times.
  """
  
  alias AshGameServer.Storage.TableSupervisor
  require Logger
  
  @component_table_prefix "component_"
  
  # Public API
  
  @doc """
  Initialize component storage for the given component definitions.
  """
  def initialize_components(component_definitions) do
    Enum.each(component_definitions, &create_component_table/1)
  end
  
  @doc """
  Store a component for an entity.
  """
  def put_component(entity_id, component_name, component_data) do
    table_name = component_table_name(component_name)
    
    case :ets.insert(table_name, {entity_id, component_data}) do
      true ->
        update_access_stats(table_name, :write)
        :ok
        
      false ->
        {:error, :insert_failed}
    end
  end
  
  @doc """
  Retrieve a component for an entity.
  """
  def get_component(entity_id, component_name) do
    table_name = component_table_name(component_name)
    
    case :ets.lookup(table_name, entity_id) do
      [{^entity_id, component_data}] ->
        update_access_stats(table_name, :read)
        {:ok, component_data}
        
      [] ->
        {:error, :not_found}
    end
  end
  
  @doc """
  Remove a component from an entity.
  """
  def delete_component(entity_id, component_name) do
    table_name = component_table_name(component_name)
    
    case :ets.delete(table_name, entity_id) do
      true ->
        update_access_stats(table_name, :delete)
        :ok
        
      false ->
        {:error, :delete_failed}
    end
  end
  
  @doc """
  Check if an entity has a specific component.
  """
  def has_component?(entity_id, component_name) do
    table_name = component_table_name(component_name)
    :ets.member(table_name, entity_id)
  end
  
  @doc """
  Get multiple components for an entity in a single operation.
  """
  def get_components(entity_id, component_names) do
    component_names
    |> Enum.reduce(%{}, fn component_name, acc ->
      case get_component(entity_id, component_name) do
        {:ok, data} ->
          Map.put(acc, component_name, data)
          
        {:error, :not_found} ->
          acc
      end
    end)
  end
  
  @doc """
  Update multiple components for an entity in a batch operation.
  """
  def put_components(entity_id, components_map) do
    results = 
      Enum.map(components_map, fn {component_name, data} ->
        put_component(entity_id, component_name, data)
      end)
    
    # Check if all operations succeeded
    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, :partial_failure, results}
    end
  end
  
  @doc """
  Get all entities that have a specific component.
  """
  def get_entities_with_component(component_name) do
    table_name = component_table_name(component_name)
    
    :ets.select(table_name, [{{:"$1", :"$2"}, [], [:"$1"]}])
  end
  
  @doc """
  Get all entities that have all of the specified components.
  """
  def get_entities_with_components(component_names) when is_list(component_names) do
    case component_names do
      [] ->
        []
        
      [first_component | rest_components] ->
        # Start with entities that have the first component
        initial_entities = get_entities_with_component(first_component)
        
        # Filter to only entities that have all other components
        Enum.filter(initial_entities, fn entity_id ->
          Enum.all?(rest_components, &has_component?(entity_id, &1))
        end)
    end
  end
  
  @doc """
  Update a component field atomically.
  """
  def update_component_field(entity_id, component_name, field_updates) do
    table_name = component_table_name(component_name)
    
    # Use ETS atomic update operations
    update_spec = [{{entity_id, :"$1"}, [], [{entity_id, {:update_fields, :"$1", field_updates}}]}]
    
    case :ets.select_replace(table_name, update_spec) do
      1 ->
        update_access_stats(table_name, :update)
        :ok
        
      0 ->
        {:error, :not_found}
        
      _other ->
        {:error, :update_failed}
    end
  end
  
  @doc """
  Get statistics for a component table.
  """
  def component_stats(component_name) do
    table_name = component_table_name(component_name)
    
    case :ets.info(table_name) do
      :undefined ->
        {:error, :table_not_found}
        
      info when is_list(info) ->
        {:ok, %{
          name: component_name,
          size: info[:size],
          memory: info[:memory],
          type: info[:type],
          protection: info[:protection],
          owner: info[:owner]
        }}
    end
  end
  
  @doc """
  Get all component statistics.
  """
  def all_component_stats do
    # This would typically iterate over known component types
    # For now, we'll use the table info from the supervisor
    TableSupervisor.table_info()
    |> Enum.filter(&String.starts_with?(to_string(&1.name), @component_table_prefix))
    |> Enum.map(fn table_info ->
      component_name = 
        table_info.name
        |> to_string()
        |> String.trim_leading(@component_table_prefix)
        |> String.to_atom()
      
      Map.put(table_info, :component_name, component_name)
    end)
  end
  
  @doc """
  Compact and optimize component tables.
  """
  def optimize_storage do
    all_component_stats()
    |> Enum.each(fn stats ->
      table_name = component_table_name(stats.component_name)
      
      # Force garbage collection of the table
      :ets.safe_fixtable(table_name, true)
      :ets.safe_fixtable(table_name, false)
    end)
    
    :ok
  end
  
  # Private Functions
  
  defp create_component_table(component_definition) do
    table_name = component_table_name(component_definition.name)
    
    case TableSupervisor.create_component_table(table_name) do
      {:ok, _table_ref} ->
        Logger.debug("Created component table: #{table_name}")
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to create component table #{table_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp component_table_name(component_name) do
    String.to_atom(@component_table_prefix <> to_string(component_name))
  end
  
  defp update_access_stats(table_name, operation) do
    # Update access statistics (could be moved to a separate monitoring process)
    stats_table = :table_stats
    timestamp = System.monotonic_time(:millisecond)
    
    # Simple counter increment - in production this might be more sophisticated
    try do
      :ets.update_counter(stats_table, {table_name, operation}, 1, {{table_name, operation}, 0})
      :ets.insert(stats_table, {{table_name, :last_access}, timestamp})
    rescue
      ArgumentError ->
        # Stats table might not exist yet, ignore
        :ok
    end
  end
end