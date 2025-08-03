defmodule AshGameServer.Storage.EntityManager do
  @moduledoc """
  Entity lifecycle management for the ECS system.
  
  This module handles:
  - Entity creation and destruction
  - Archetype instantiation
  - Component composition
  - Entity queries and lookup
  """
  
  alias AshGameServer.Storage.ComponentStorage
  alias AshGameServer.Storage.TableSupervisor
  require Logger
  
  @entity_registry_table :entity_registry
  @entity_id_counter :entity_id_counter
  
  # Public API
  
  @doc """
  Initialize the entity management system.
  """
  def initialize do
    # Create entity registry table
    TableSupervisor.create_component_table(@entity_registry_table)
    
    # Create entity ID counter table
    TableSupervisor.create_component_table(@entity_id_counter)
    :ets.insert(@entity_id_counter, {:next_id, 1})
    
    Logger.info("Entity management system initialized")
    :ok
  end
  
  @doc """
  Create a new entity with optional archetype and initial components.
  """
  def create_entity(opts \\ []) do
    entity_id = generate_entity_id()
    archetype = Keyword.get(opts, :archetype)
    initial_components = Keyword.get(opts, :components, %{})
    
    # Create entity record
    entity_data = %{
      id: entity_id,
      archetype: archetype,
      components: [],
      created_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    
    :ets.insert(@entity_registry_table, {entity_id, entity_data})
    
    # Apply archetype if specified
    if archetype do
      apply_archetype(entity_id, archetype)
    end
    
    # Add initial components
    if map_size(initial_components) > 0 do
      add_components(entity_id, initial_components)
    end
    
    Logger.debug("Created entity #{entity_id} with archetype #{archetype}")
    {:ok, entity_id}
  end
  
  @doc """
  Destroy an entity and clean up all its components.
  """
  def destroy_entity(entity_id) do
    case get_entity(entity_id) do
      {:ok, entity_data} ->
        # Remove all components
        Enum.each(entity_data.components, fn component_name ->
          ComponentStorage.delete_component(entity_id, component_name)
        end)
        
        # Remove from registry
        :ets.delete(@entity_registry_table, entity_id)
        
        Logger.debug("Destroyed entity #{entity_id}")
        :ok
        
      {:error, :not_found} ->
        {:error, :entity_not_found}
    end
  end
  
  @doc """
  Get entity information from the registry.
  """
  def get_entity(entity_id) do
    case :ets.lookup(@entity_registry_table, entity_id) do
      [{^entity_id, entity_data}] ->
        {:ok, entity_data}
        
      [] ->
        {:error, :not_found}
    end
  end
  
  @doc """
  Check if an entity exists.
  """
  def entity_exists?(entity_id) do
    :ets.member(@entity_registry_table, entity_id)
  end
  
  @doc """
  Add a component to an entity.
  """
  def add_component(entity_id, component_name, component_data) do
    with {:ok, entity_data} <- get_entity(entity_id),
         :ok <- ComponentStorage.put_component(entity_id, component_name, component_data) do
      
      # Update entity registry
      updated_components = [component_name | entity_data.components] |> Enum.uniq()
      updated_entity_data = %{entity_data | components: updated_components}
      :ets.insert(@entity_registry_table, {entity_id, updated_entity_data})
      
      :ok
    else
      {:error, :not_found} ->
        {:error, :entity_not_found}
        
      error ->
        error
    end
  end
  
  @doc """
  Remove a component from an entity.
  """
  def remove_component(entity_id, component_name) do
    with {:ok, entity_data} <- get_entity(entity_id),
         :ok <- ComponentStorage.delete_component(entity_id, component_name) do
      
      # Update entity registry
      updated_components = List.delete(entity_data.components, component_name)
      updated_entity_data = %{entity_data | components: updated_components}
      :ets.insert(@entity_registry_table, {entity_id, updated_entity_data})
      
      :ok
    else
      {:error, :not_found} ->
        {:error, :entity_not_found}
        
      error ->
        error
    end
  end
  
  @doc """
  Add multiple components to an entity.
  """
  def add_components(entity_id, components_map) do
    results = 
      Enum.map(components_map, fn {component_name, data} ->
        add_component(entity_id, component_name, data)
      end)
    
    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, :partial_failure, results}
    end
  end
  
  @doc """
  Get all components for an entity.
  """
  def get_entity_components(entity_id) do
    case get_entity(entity_id) do
      {:ok, entity_data} ->
        component_data = ComponentStorage.get_components(entity_id, entity_data.components)
        {:ok, component_data}
        
      error ->
        error
    end
  end
  
  @doc """
  Apply an archetype to an entity.
  """
  def apply_archetype(entity_id, archetype_name) do
    # This would look up the archetype definition and apply its components
    # For now, we'll use a simple implementation
    archetype_components = get_archetype_components(archetype_name)
    
    add_components(entity_id, archetype_components)
  end
  
  @doc """
  Query entities by component requirements.
  """
  def query_entities(required_components, optional_components \\ []) do
    entities_with_required = ComponentStorage.get_entities_with_components(required_components)
    
    # Add component data for matching entities
    Enum.map(entities_with_required, fn entity_id ->
      all_requested_components = required_components ++ optional_components
      component_data = ComponentStorage.get_components(entity_id, all_requested_components)
      
      %{
        entity_id: entity_id,
        components: component_data
      }
    end)
  end
  
  @doc """
  Get all entities with a specific archetype.
  """
  def get_entities_by_archetype(archetype_name) do
    match_spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :archetype, :"$2"}, archetype_name}], [:"$1"]}]
    :ets.select(@entity_registry_table, match_spec)
  end
  
  @doc """
  Get entity count and statistics.
  """
  def entity_stats do
    total_entities = :ets.info(@entity_registry_table, :size)
    memory_usage = :ets.info(@entity_registry_table, :memory)
    
    # Get archetype distribution
    archetype_counts = 
      :ets.select(@entity_registry_table, [{{:"$1", :"$2"}, [], [{{:map_get, :archetype, :"$2"}, 1}]}])
      |> Enum.reduce(%{}, fn {archetype, count}, acc ->
        Map.update(acc, archetype, count, &(&1 + count))
      end)
    
    %{
      total_entities: total_entities,
      memory_usage: memory_usage,
      archetype_distribution: archetype_counts
    }
  end
  
  @doc """
  Cleanup orphaned entities (entities with no components).
  """
  def cleanup_orphaned_entities do
    orphaned_entities = 
      :ets.select(@entity_registry_table, [{{:"$1", :"$2"}, [{:==, {:map_get, :components, :"$2"}, []}], [:"$1"]}])
    
    Enum.each(orphaned_entities, &destroy_entity/1)
    
    {:ok, length(orphaned_entities)}
  end
  
  # Private Functions
  
  defp generate_entity_id do
    :ets.update_counter(@entity_id_counter, :next_id, 1)
  end
  
  defp get_archetype_components(archetype_name) do
    # This would typically look up archetype definitions from the DSL
    # For now, return some example components based on archetype name
    case archetype_name do
      :player ->
        %{
          position: %{x: 0.0, y: 0.0, z: 0.0},
          health: %{current: 100, max: 100},
          inventory: %{slots: 20, items: [], weight: 0.0}
        }
        
      :enemy ->
        %{
          position: %{x: 0.0, y: 0.0, z: 0.0},
          health: %{current: 50, max: 50},
          ai_controller: %{behavior: :aggressive, target_id: nil}
        }
        
      _ ->
        %{}
    end
  end
end