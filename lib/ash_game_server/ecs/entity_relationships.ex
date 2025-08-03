defmodule AshGameServer.ECS.EntityRelationships do
  @moduledoc """
  Entity Relationship management system for the ECS architecture.
  
  Provides comprehensive relationship management with:
  - Parent-child hierarchies with inheritance
  - Entity groups and collections
  - Relationship queries and navigation
  - Automatic cleanup and cascade operations
  - Performance optimized relationship tracking
  """

  use GenServer

  alias AshGameServer.ECS.Entity
  alias AshGameServer.ECS.EntityRegistry

  @type entity_id :: Entity.entity_id()
  @type relationship_type :: :parent | :child | :group_member | :group_owner | :linked
  @type group_id :: atom() | String.t()
  @type hierarchy_level :: non_neg_integer()
  
  @type relationship :: %{
    from_entity: entity_id(),
    to_entity: entity_id(),
    type: relationship_type(),
    metadata: map(),
    created_at: DateTime.t()
  }

  @type entity_group :: %{
    id: group_id(),
    name: String.t(),
    description: String.t(),
    owner: entity_id() | nil,
    members: [entity_id()],
    group_type: atom(),
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  # ETS tables for relationship storage
  @relationships_table :entity_relationships
  @groups_table :entity_groups
  @group_members_table :entity_group_members
  @hierarchy_cache_table :entity_hierarchy_cache

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Parent-Child Relationships

  @doc """
  Establish a parent-child relationship between entities.
  """
  @spec add_child(entity_id(), entity_id(), map()) :: :ok | {:error, term()}
  def add_child(parent_id, child_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:add_child, parent_id, child_id, metadata})
  end

  @doc """
  Remove a parent-child relationship.
  """
  @spec remove_child(entity_id(), entity_id()) :: :ok | {:error, term()}
  def remove_child(parent_id, child_id) do
    GenServer.call(__MODULE__, {:remove_child, parent_id, child_id})
  end

  @doc """
  Get all children of an entity.
  """
  @spec get_children(entity_id()) :: [entity_id()]
  def get_children(parent_id) do
    case EntityRegistry.get_entity(parent_id) do
      {:ok, entity} -> entity.children
      _ -> []
    end
  end

  @doc """
  Get the parent of an entity.
  """
  @spec get_parent(entity_id()) :: entity_id() | nil
  def get_parent(child_id) do
    case EntityRegistry.get_entity(child_id) do
      {:ok, entity} -> entity.parent_id
      _ -> nil
    end
  end

  @doc """
  Get all descendants of an entity (recursive).
  """
  @spec get_descendants(entity_id()) :: [entity_id()]
  def get_descendants(entity_id) do
    GenServer.call(__MODULE__, {:get_descendants, entity_id})
  end

  @doc """
  Get all ancestors of an entity (recursive).
  """
  @spec get_ancestors(entity_id()) :: [entity_id()]
  def get_ancestors(entity_id) do
    GenServer.call(__MODULE__, {:get_ancestors, entity_id})
  end

  @doc """
  Get the hierarchy level of an entity (0 = root).
  """
  @spec get_hierarchy_level(entity_id()) :: hierarchy_level()
  def get_hierarchy_level(entity_id) do
    case :ets.lookup(@hierarchy_cache_table, entity_id) do
      [{^entity_id, level}] -> level
      [] -> 
        # Calculate and cache
        level = calculate_hierarchy_level(entity_id)
        :ets.insert(@hierarchy_cache_table, {entity_id, level})
        level
    end
  end

  @doc """
  Check if entity A is an ancestor of entity B.
  """
  @spec ancestor?(entity_id(), entity_id()) :: boolean()
  def ancestor?(ancestor_id, descendant_id) do
    ancestor_id in get_ancestors(descendant_id)
  end

  @doc """
  Check if entity A is a descendant of entity B.
  """
  @spec descendant?(entity_id(), entity_id()) :: boolean()
  def descendant?(descendant_id, ancestor_id) do
    descendant_id in get_descendants(ancestor_id)
  end

  # Entity Groups

  @doc """
  Create a new entity group.
  """
  @spec create_group(group_id(), String.t(), keyword()) :: {:ok, entity_group()} | {:error, term()}
  def create_group(group_id, name, opts \\ []) do
    GenServer.call(__MODULE__, {:create_group, group_id, name, opts})
  end

  @doc """
  Delete an entity group.
  """
  @spec delete_group(group_id()) :: :ok | {:error, term()}
  def delete_group(group_id) do
    GenServer.call(__MODULE__, {:delete_group, group_id})
  end

  @doc """
  Add an entity to a group.
  """
  @spec add_to_group(entity_id(), group_id()) :: :ok | {:error, term()}
  def add_to_group(entity_id, group_id) do
    GenServer.call(__MODULE__, {:add_to_group, entity_id, group_id})
  end

  @doc """
  Remove an entity from a group.
  """
  @spec remove_from_group(entity_id(), group_id()) :: :ok | {:error, term()}
  def remove_from_group(entity_id, group_id) do
    GenServer.call(__MODULE__, {:remove_from_group, entity_id, group_id})
  end

  @doc """
  Get all members of a group.
  """
  @spec get_group_members(group_id()) :: [entity_id()]
  def get_group_members(group_id) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] -> group.members
      [] -> []
    end
  end

  @doc """
  Get all groups an entity belongs to.
  """
  @spec get_entity_groups(entity_id()) :: [group_id()]
  def get_entity_groups(entity_id) do
    :ets.select(@group_members_table, [{{entity_id, :"$1"}, [], [:"$1"]}])
  end

  @doc """
  Get group information.
  """
  @spec get_group(group_id()) :: {:ok, entity_group()} | {:error, :not_found}
  def get_group(group_id) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] -> {:ok, group}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all groups.
  """
  @spec list_groups() :: [entity_group()]
  def list_groups do
    :ets.select(@groups_table, [{{:"$1", :"$2"}, [], [:"$2"]}])
  end

  @doc """
  Update group metadata.
  """
  @spec update_group(group_id(), map()) :: :ok | {:error, term()}
  def update_group(group_id, updates) do
    GenServer.call(__MODULE__, {:update_group, group_id, updates})
  end

  # Generic Relationships

  @doc """
  Create a custom relationship between entities.
  """
  @spec create_relationship(entity_id(), entity_id(), relationship_type(), map()) :: 
    :ok | {:error, term()}
  def create_relationship(from_entity, to_entity, type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:create_relationship, from_entity, to_entity, type, metadata})
  end

  @doc """
  Remove a relationship between entities.
  """
  @spec remove_relationship(entity_id(), entity_id(), relationship_type()) :: :ok
  def remove_relationship(from_entity, to_entity, type) do
    GenServer.cast(__MODULE__, {:remove_relationship, from_entity, to_entity, type})
  end

  @doc """
  Get all relationships for an entity.
  """
  @spec get_relationships(entity_id()) :: [relationship()]
  def get_relationships(entity_id) do
    outgoing = :ets.select(@relationships_table, [
      {{{entity_id, :"$1"}, :"$2"}, [], [:"$2"]}
    ])
    
    incoming = :ets.select(@relationships_table, [
      {{{:"$1", entity_id}, :"$2"}, [], [:"$2"]}
    ])
    
    outgoing ++ incoming
  end

  @doc """
  Get relationships of a specific type for an entity.
  """
  @spec get_relationships_by_type(entity_id(), relationship_type()) :: [relationship()]
  def get_relationships_by_type(entity_id, type) do
    get_relationships(entity_id)
    |> Enum.filter(&(&1.type == type))
  end

  @doc """
  Check if two entities have a specific relationship.
  """
  @spec has_relationship?(entity_id(), entity_id(), relationship_type()) :: boolean()
  def has_relationship?(from_entity, to_entity, type) do
    case :ets.lookup(@relationships_table, {from_entity, to_entity}) do
      [{_, relationship}] -> relationship.type == type
      [] -> false
    end
  end

  # Cascade Operations

  @doc """
  Perform cascade operations when an entity is destroyed.
  """
  @spec cascade_destroy(entity_id()) :: :ok
  def cascade_destroy(entity_id) do
    GenServer.cast(__MODULE__, {:cascade_destroy, entity_id})
  end

  @doc """
  Get relationship statistics.
  """
  @spec get_relationship_stats() :: map()
  def get_relationship_stats do
    GenServer.call(__MODULE__, :get_relationship_stats)
  end

  # Navigation Utilities

  @doc """
  Find the root entity in a hierarchy.
  """
  @spec find_root(entity_id()) :: entity_id()
  def find_root(entity_id) do
    case get_parent(entity_id) do
      nil -> entity_id
      parent_id -> find_root(parent_id)
    end
  end

  @doc """
  Get all siblings of an entity.
  """
  @spec get_siblings(entity_id()) :: [entity_id()]
  def get_siblings(entity_id) do
    case get_parent(entity_id) do
      nil -> []
      parent_id -> 
        get_children(parent_id)
        |> Enum.reject(&(&1 == entity_id))
    end
  end

  @doc """
  Get entities at a specific hierarchy level.
  """
  @spec get_entities_at_level(hierarchy_level()) :: [entity_id()]
  def get_entities_at_level(level) do
    :ets.select(@hierarchy_cache_table, [{{:"$1", level}, [], [:"$1"]}])
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create relationship storage tables
    :ets.new(@relationships_table, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@groups_table, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@group_members_table, [:named_table, :public, :bag])
    :ets.new(@hierarchy_cache_table, [:named_table, :public, :set])

    state = %{
      relationship_count: 0,
      group_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_child, parent_id, child_id, metadata}, _from, state) do
    result = do_add_child(parent_id, child_id, metadata)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_child, parent_id, child_id}, _from, state) do
    result = do_remove_child(parent_id, child_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_descendants, entity_id}, _from, state) do
    descendants = collect_descendants(entity_id, [])
    {:reply, descendants, state}
  end

  @impl true
  def handle_call({:get_ancestors, entity_id}, _from, state) do
    ancestors = collect_ancestors(entity_id, [])
    {:reply, ancestors, state}
  end

  @impl true
  def handle_call({:create_group, group_id, name, opts}, _from, state) do
    result = do_create_group(group_id, name, opts)
    new_state = %{state | group_count: state.group_count + 1}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:delete_group, group_id}, _from, state) do
    result = do_delete_group(group_id)
    new_state = case result do
      :ok -> %{state | group_count: max(0, state.group_count - 1)}
      _ -> state
    end
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:add_to_group, entity_id, group_id}, _from, state) do
    result = do_add_to_group(entity_id, group_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_from_group, entity_id, group_id}, _from, state) do
    result = do_remove_from_group(entity_id, group_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_group, group_id, updates}, _from, state) do
    result = do_update_group(group_id, updates)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_relationship, from_entity, to_entity, type, metadata}, _from, state) do
    result = do_create_relationship(from_entity, to_entity, type, metadata)
    new_state = case result do
      :ok -> %{state | relationship_count: state.relationship_count + 1}
      _ -> state
    end
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_relationship_stats, _from, state) do
    stats = %{
      total_relationships: state.relationship_count,
      total_groups: state.group_count,
      hierarchy_cache_size: :ets.info(@hierarchy_cache_table, :size),
      group_memberships: :ets.info(@group_members_table, :size)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:remove_relationship, from_entity, to_entity, type}, state) do
    do_remove_relationship(from_entity, to_entity, type)
    new_state = %{state | relationship_count: max(0, state.relationship_count - 1)}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:cascade_destroy, entity_id}, state) do
    do_cascade_destroy(entity_id)
    {:noreply, state}
  end

  # Private Functions

  defp do_add_child(parent_id, child_id, metadata) do
    with {:ok, parent} <- EntityRegistry.get_entity(parent_id),
         {:ok, child} <- EntityRegistry.get_entity(child_id),
         :ok <- validate_child_addition(parent_id, child_id) do
      
      # Update parent entity
      updated_children = [child_id | parent.children] |> Enum.uniq()
      updated_parent = %{parent | 
        children: updated_children,
        updated_at: DateTime.utc_now(),
        version: parent.version + 1
      }
      
      # Update child entity
      updated_child = %{child |
        parent_id: parent_id,
        updated_at: DateTime.utc_now(),
        version: child.version + 1
      }
      
      # Store updates
      EntityRegistry.update_entity(updated_parent)
      EntityRegistry.update_entity(updated_child)
      
      # Create relationship record
      relationship = %{
        from_entity: parent_id,
        to_entity: child_id,
        type: :parent,
        metadata: metadata,
        created_at: DateTime.utc_now()
      }
      
      :ets.insert(@relationships_table, {{parent_id, child_id}, relationship})
      
      # Invalidate hierarchy cache for affected entities
      invalidate_hierarchy_cache(parent_id)
      invalidate_hierarchy_cache(child_id)
      
      :ok
    end
  end

  defp do_remove_child(parent_id, child_id) do
    with {:ok, parent} <- EntityRegistry.get_entity(parent_id),
         {:ok, child} <- EntityRegistry.get_entity(child_id) do
      
      # Update parent entity
      updated_children = List.delete(parent.children, child_id)
      updated_parent = %{parent |
        children: updated_children,
        updated_at: DateTime.utc_now(),
        version: parent.version + 1
      }
      
      # Update child entity
      updated_child = %{child |
        parent_id: nil,
        updated_at: DateTime.utc_now(),
        version: child.version + 1
      }
      
      # Store updates
      EntityRegistry.update_entity(updated_parent)
      EntityRegistry.update_entity(updated_child)
      
      # Remove relationship record
      :ets.delete(@relationships_table, {parent_id, child_id})
      
      # Invalidate hierarchy cache
      invalidate_hierarchy_cache(parent_id)
      invalidate_hierarchy_cache(child_id)
      
      :ok
    end
  end

  defp validate_child_addition(parent_id, child_id) do
    cond do
      parent_id == child_id ->
        {:error, :cannot_parent_self}
      
      ancestor?(child_id, parent_id) ->
        {:error, :would_create_cycle}
      
      true -> :ok
    end
  end

  defp collect_descendants(entity_id, visited) do
    if entity_id in visited do
      []  # Prevent infinite loops
    else
      children = get_children(entity_id)
      direct_descendants = children
      
      indirect_descendants = 
        Enum.flat_map(children, fn child_id ->
          collect_descendants(child_id, [entity_id | visited])
        end)
      
      Enum.uniq(direct_descendants ++ indirect_descendants)
    end
  end

  defp collect_ancestors(entity_id, visited) do
    if entity_id in visited do
      []  # Prevent infinite loops
    else
      case get_parent(entity_id) do
        nil -> []
        parent_id ->
          [parent_id | collect_ancestors(parent_id, [entity_id | visited])]
      end
    end
  end

  defp calculate_hierarchy_level(entity_id) do
    case get_parent(entity_id) do
      nil -> 0
      parent_id -> 1 + get_hierarchy_level(parent_id)
    end
  end

  defp invalidate_hierarchy_cache(entity_id) do
    # Remove from cache - will be recalculated on next access
    :ets.delete(@hierarchy_cache_table, entity_id)
    
    # Also invalidate descendants
    descendants = collect_descendants(entity_id, [])
    Enum.each(descendants, fn descendant_id ->
      :ets.delete(@hierarchy_cache_table, descendant_id)
    end)
  end

  defp do_create_group(group_id, name, opts) do
    case :ets.lookup(@groups_table, group_id) do
      [] ->
        group = %{
          id: group_id,
          name: name,
          description: Keyword.get(opts, :description, ""),
          owner: Keyword.get(opts, :owner),
          members: [],
          group_type: Keyword.get(opts, :group_type, :general),
          metadata: Keyword.get(opts, :metadata, %{}),
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
        
        :ets.insert(@groups_table, {group_id, group})
        {:ok, group}
      
      _ ->
        {:error, :group_already_exists}
    end
  end

  defp do_delete_group(group_id) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] ->
        # Remove all group memberships
        Enum.each(group.members, fn member_id ->
          :ets.delete_object(@group_members_table, {member_id, group_id})
        end)
        
        # Remove group
        :ets.delete(@groups_table, group_id)
        :ok
      
      [] ->
        {:error, :group_not_found}
    end
  end

  defp do_add_to_group(entity_id, group_id) do
    case EntityRegistry.exists?(entity_id) do
      true ->
        case :ets.lookup(@groups_table, group_id) do
          [{^group_id, group}] ->
            if entity_id in group.members do
              {:error, :already_member}
            else
              # Update group
              updated_members = [entity_id | group.members]
              updated_group = %{group |
                members: updated_members,
                updated_at: DateTime.utc_now()
              }
              
              :ets.insert(@groups_table, {group_id, updated_group})
              :ets.insert(@group_members_table, {entity_id, group_id})
              
              :ok
            end
          
          [] ->
            {:error, :group_not_found}
        end
      
      false ->
        {:error, :entity_not_found}
    end
  end

  defp do_remove_from_group(entity_id, group_id) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] ->
        updated_members = List.delete(group.members, entity_id)
        updated_group = %{group |
          members: updated_members,
          updated_at: DateTime.utc_now()
        }
        
        :ets.insert(@groups_table, {group_id, updated_group})
        :ets.delete_object(@group_members_table, {entity_id, group_id})
        
        :ok
      
      [] ->
        {:error, :group_not_found}
    end
  end

  defp do_update_group(group_id, updates) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] ->
        updated_group = %{Map.merge(group, updates) | updated_at: DateTime.utc_now()}
        :ets.insert(@groups_table, {group_id, updated_group})
        :ok
      
      [] ->
        {:error, :group_not_found}
    end
  end

  defp do_create_relationship(from_entity, to_entity, type, metadata) do
    with true <- EntityRegistry.exists?(from_entity),
         true <- EntityRegistry.exists?(to_entity) do
      
      relationship = %{
        from_entity: from_entity,
        to_entity: to_entity,
        type: type,
        metadata: metadata,
        created_at: DateTime.utc_now()
      }
      
      :ets.insert(@relationships_table, {{from_entity, to_entity}, relationship})
      :ok
    else
      false -> {:error, :entity_not_found}
    end
  end

  defp do_remove_relationship(from_entity, to_entity, _type) do
    :ets.delete(@relationships_table, {from_entity, to_entity})
  end

  defp do_cascade_destroy(entity_id) do
    # Remove from all groups
    groups = get_entity_groups(entity_id)
    Enum.each(groups, fn group_id ->
      do_remove_from_group(entity_id, group_id)
    end)
    
    # Remove all relationships involving this entity
    relationships = get_relationships(entity_id)
    Enum.each(relationships, fn relationship ->
      if relationship.from_entity == entity_id do
        :ets.delete(@relationships_table, {relationship.from_entity, relationship.to_entity})
      else
        :ets.delete(@relationships_table, {relationship.from_entity, relationship.to_entity})
      end
    end)
    
    # Remove from hierarchy cache
    :ets.delete(@hierarchy_cache_table, entity_id)
    
    :ok
  end
end