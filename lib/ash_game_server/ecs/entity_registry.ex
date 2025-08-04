defmodule AshGameServer.ECS.EntityRegistry do
  @moduledoc """
  Centralized entity tracking and registry system for the ECS architecture.

  Provides comprehensive entity management with:
  - Centralized entity tracking and lookup
  - Advanced entity queries and indexing
  - Entity statistics and monitoring
  - Garbage collection and cleanup
  - Performance optimization
  """

  use GenServer

  alias AshGameServer.ECS.Entity

  @type entity_id :: Entity.entity_id()
  @type entity :: Entity.entity()
  @type query_filter :: map()
  @type index_name :: atom()
  @type statistics :: map()

  # ETS table names
  @entities_table :entity_registry
  @status_index :entity_status_index
  @archetype_index :entity_archetype_index
  @parent_index :entity_parent_index
  @tag_index :entity_tag_index
  @statistics_table :entity_statistics

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new entity in the registry.
  """
  @spec register_entity(entity()) :: :ok | {:error, term()}
  def register_entity(entity) do
    GenServer.call(__MODULE__, {:register_entity, entity})
  end

  @doc """
  Update an existing entity in the registry.
  """
  @spec update_entity(entity()) :: :ok | {:error, term()}
  def update_entity(entity) do
    GenServer.call(__MODULE__, {:update_entity, entity})
  end

  @doc """
  Get an entity by ID.
  """
  @spec get_entity(entity_id()) :: {:ok, entity()} | {:error, :not_found}
  def get_entity(entity_id) do
    case :ets.lookup(@entities_table, entity_id) do
      [{^entity_id, entity}] -> {:ok, entity}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Check if an entity exists.
  """
  @spec exists?(entity_id()) :: boolean()
  def exists?(entity_id) do
    :ets.member(@entities_table, entity_id)
  end

  @doc """
  Unregister an entity from the registry.
  """
  @spec unregister_entity(entity_id()) :: :ok
  def unregister_entity(entity_id) do
    GenServer.call(__MODULE__, {:unregister_entity, entity_id})
  end

  # Entity Queries

  @doc """
  Query entities by status.
  """
  @spec query_by_status(Entity.entity_status()) :: [entity_id()]
  def query_by_status(status) do
    :ets.select(@status_index, [{{status, :"$1"}, [], [:"$1"]}])
    |> List.flatten()
  end

  @doc """
  Query entities by archetype.
  """
  @spec query_by_archetype(Entity.archetype_name()) :: [entity_id()]
  def query_by_archetype(archetype) do
    :ets.select(@archetype_index, [{{archetype, :"$1"}, [], [:"$1"]}])
    |> List.flatten()
  end

  @doc """
  Query entities by parent ID.
  """
  @spec query_by_parent(entity_id()) :: [entity_id()]
  def query_by_parent(parent_id) do
    :ets.select(@parent_index, [{{parent_id, :"$1"}, [], [:"$1"]}])
    |> List.flatten()
  end

  @doc """
  Query entities by tag.
  """
  @spec query_by_tag(atom()) :: [entity_id()]
  def query_by_tag(tag) do
    :ets.select(@tag_index, [{{tag, :"$1"}, [], [:"$1"]}])
    |> List.flatten()
  end

  @doc """
  Advanced entity query with multiple filters.
  """
  @spec query_entities(query_filter()) :: [entity()]
  def query_entities(filters) do
    GenServer.call(__MODULE__, {:query_entities, filters})
  end

  @doc """
  Query entities with pagination.
  """
  @spec query_entities_paginated(query_filter(), non_neg_integer(), pos_integer()) ::
    {[entity()], boolean()}
  def query_entities_paginated(filters, offset, limit) do
    GenServer.call(__MODULE__, {:query_entities_paginated, filters, offset, limit})
  end

  # Entity Statistics

  @doc """
  Get comprehensive entity statistics.
  """
  @spec get_statistics() :: statistics()
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Get entity count by status.
  """
  @spec count_by_status() :: %{Entity.entity_status() => non_neg_integer()}
  def count_by_status do
    :ets.foldl(fn {status, _entity_id}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end, %{}, @status_index)
  end

  @doc """
  Get entity count by archetype.
  """
  @spec count_by_archetype() :: %{Entity.archetype_name() => non_neg_integer()}
  def count_by_archetype do
    :ets.foldl(fn {archetype, _entity_id}, acc ->
      Map.update(acc, archetype, 1, &(&1 + 1))
    end, %{}, @archetype_index)
  end

  @doc """
  Get total entity count.
  """
  @spec total_count() :: non_neg_integer()
  def total_count do
    :ets.info(@entities_table, :size)
  end

  # Garbage Collection

  @doc """
  Perform garbage collection on destroyed entities.
  """
  @spec garbage_collect() :: {:ok, non_neg_integer()}
  def garbage_collect do
    GenServer.call(__MODULE__, :garbage_collect)
  end

  @doc """
  Clean up entities older than the specified age.
  """
  @spec cleanup_old_entities(non_neg_integer()) :: {:ok, non_neg_integer()}
  def cleanup_old_entities(max_age_seconds) do
    GenServer.call(__MODULE__, {:cleanup_old_entities, max_age_seconds})
  end

  # Performance and Monitoring

  @doc """
  Get memory usage statistics.
  """
  @spec memory_usage() :: map()
  def memory_usage do
    %{
      entities_table: :ets.info(@entities_table, :memory) * 8,
      status_index: :ets.info(@status_index, :memory) * 8,
      archetype_index: :ets.info(@archetype_index, :memory) * 8,
      parent_index: :ets.info(@parent_index, :memory) * 8,
      tag_index: :ets.info(@tag_index, :memory) * 8,
      statistics_table: :ets.info(@statistics_table, :memory) * 8
    }
  end

  @doc """
  Rebuild all indexes for performance optimization.
  """
  @spec rebuild_indexes() :: :ok
  def rebuild_indexes do
    GenServer.cast(__MODULE__, :rebuild_indexes)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create main entities table
    :ets.new(@entities_table, [:named_table, :public, :set, {:read_concurrency, true}])

    # Create index tables
    :ets.new(@status_index, [:named_table, :public, :bag])
    :ets.new(@archetype_index, [:named_table, :public, :bag])
    :ets.new(@parent_index, [:named_table, :public, :bag])
    :ets.new(@tag_index, [:named_table, :public, :bag])

    # Create statistics table
    :ets.new(@statistics_table, [:named_table, :public, :set])

    # Initialize statistics
    initialize_statistics()

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      cleanup_interval: 300_000,  # 5 minutes
      gc_threshold: 1000,         # Run GC when 1000+ destroyed entities
      statistics_interval: 60_000 # Update stats every minute
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_entity, entity}, _from, state) do
    result = do_register_entity(entity)
    update_statistics(:entity_created)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_entity, entity}, _from, state) do
    result = do_update_entity(entity)
    update_statistics(:entity_updated)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:query_entities, filters}, _from, state) do
    entities = do_query_entities(filters)
    update_statistics(:query_executed)
    {:reply, entities, state}
  end

  @impl true
  def handle_call({:query_entities_paginated, filters, offset, limit}, _from, state) do
    result = do_query_entities_paginated(filters, offset, limit)
    update_statistics(:query_executed)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    stats = compile_statistics()
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:garbage_collect, _from, state) do
    collected = do_garbage_collect()
    update_statistics(:gc_executed)
    {:reply, {:ok, collected}, state}
  end

  @impl true
  def handle_call({:cleanup_old_entities, max_age_seconds}, _from, state) do
    cleaned = do_cleanup_old_entities(max_age_seconds)
    update_statistics(:cleanup_executed)
    {:reply, {:ok, cleaned}, state}
  end

  @impl true
  def handle_call({:unregister_entity, entity_id}, _from, state) do
    do_unregister_entity(entity_id)
    update_statistics(:entity_unregistered)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:rebuild_indexes, state) do
    do_rebuild_indexes()
    update_statistics(:indexes_rebuilt)
    {:noreply, state}
  end

  @impl true
  def handle_info(:periodic_cleanup, state) do
    # Perform periodic maintenance
    do_garbage_collect()
    do_cleanup_old_entities(3600)  # Clean entities older than 1 hour
    update_periodic_statistics()

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, state}
  end

  @impl true
  def handle_info(:update_statistics, state) do
    update_periodic_statistics()
    schedule_statistics_update()
    {:noreply, state}
  end

  # Private Functions

  defp do_register_entity(entity) do
    # Store in main table
    :ets.insert(@entities_table, {entity.id, entity})

    # Update indexes
    update_indexes_for_entity(entity, nil)

    :ok
  end

  defp do_update_entity(entity) do
    # Get old entity for index cleanup
    old_entity = case :ets.lookup(@entities_table, entity.id) do
      [{_, old}] -> old
      [] -> nil
    end

    # Update main table
    :ets.insert(@entities_table, {entity.id, entity})

    # Update indexes
    update_indexes_for_entity(entity, old_entity)

    :ok
  end

  defp do_unregister_entity(entity_id) do
    case :ets.lookup(@entities_table, entity_id) do
      [{_, entity}] ->
        # Remove from main table
        :ets.delete(@entities_table, entity_id)

        # Clean up indexes
        cleanup_indexes_for_entity(entity)

        :ok

      [] -> :ok
    end
  end

  defp update_indexes_for_entity(entity, old_entity) do
    # Clean up old indexes if updating
    if old_entity do
      cleanup_indexes_for_entity(old_entity)
    end

    # Status index
    add_to_index(@status_index, entity.status, entity.id)

    # Archetype index
    if entity.archetype do
      add_to_index(@archetype_index, entity.archetype, entity.id)
    end

    # Parent index
    if entity.parent_id do
      add_to_index(@parent_index, entity.parent_id, entity.id)
    end

    # Tag indexes
    Enum.each(entity.tags, fn tag ->
      add_to_index(@tag_index, tag, entity.id)
    end)
  end

  defp cleanup_indexes_for_entity(entity) do
    # Status index
    remove_from_index(@status_index, entity.status, entity.id)

    # Archetype index
    if entity.archetype do
      remove_from_index(@archetype_index, entity.archetype, entity.id)
    end

    # Parent index
    if entity.parent_id do
      remove_from_index(@parent_index, entity.parent_id, entity.id)
    end

    # Tag indexes
    Enum.each(entity.tags, fn tag ->
      remove_from_index(@tag_index, tag, entity.id)
    end)
  end

  defp add_to_index(table, key, entity_id) do
    :ets.insert(table, {key, entity_id})
  end

  defp remove_from_index(table, key, entity_id) do
    :ets.delete_object(table, {key, entity_id})
  end

  defp do_query_entities(filters) do
    # Start with all entities
    entity_ids = get_candidate_entity_ids(filters)

    # Filter based on criteria
    entity_ids
    |> Enum.map(&get_entity/1)
    |> Enum.filter(&(elem(&1, 0) == :ok))
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&entity_matches_filters?(&1, filters))
  end

  defp do_query_entities_paginated(filters, offset, limit) do
    entities = do_query_entities(filters)
    total_count = length(entities)

    paginated_entities =
      entities
      |> Enum.drop(offset)
      |> Enum.take(limit)

    has_more = (offset + limit) < total_count

    {paginated_entities, has_more}
  end

  defp get_candidate_entity_ids(filters) do
    # Use the most selective filter to get initial candidates
    cond do
      Map.has_key?(filters, :status) ->
        query_by_status(filters.status)

      Map.has_key?(filters, :archetype) ->
        query_by_archetype(filters.archetype)

      Map.has_key?(filters, :parent_id) ->
        query_by_parent(filters.parent_id)

      Map.has_key?(filters, :tag) ->
        query_by_tag(filters.tag)

      true ->
        # Get all entity IDs
        :ets.select(@entities_table, [{{:"$1", :_}, [], [:"$1"]}])
    end
  end

  defp entity_matches_filters?(entity, filters) do
    Enum.all?(filters, fn filter -> matches_single_filter?(entity, filter) end)
  end

  defp matches_single_filter?(entity, {:status, value}), do: entity.status == value
  defp matches_single_filter?(entity, {:archetype, value}), do: entity.archetype == value
  defp matches_single_filter?(entity, {:parent_id, value}), do: entity.parent_id == value
  defp matches_single_filter?(entity, {:tag, value}), do: value in entity.tags
  defp matches_single_filter?(entity, {:min_version, value}), do: entity.version >= value
  defp matches_single_filter?(entity, {:max_version, value}), do: entity.version <= value
  defp matches_single_filter?(entity, {:created_after, value}), do: DateTime.compare(entity.created_at, value) in [:gt, :eq]
  defp matches_single_filter?(entity, {:created_before, value}), do: DateTime.compare(entity.created_at, value) in [:lt, :eq]
  defp matches_single_filter?(entity, {:has_components, value}), do: Enum.all?(value, &(&1 in entity.components))
  defp matches_single_filter?(_entity, _), do: true

  defp do_garbage_collect do
    destroyed_entities = query_by_status(:destroyed)

    cutoff_time = DateTime.add(DateTime.utc_now(), -300, :second)  # 5 minutes ago

    old_destroyed =
      destroyed_entities
      |> Enum.map(&get_entity/1)
      |> Enum.filter(&(elem(&1, 0) == :ok))
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(DateTime.compare(&1.updated_at, cutoff_time) == :lt))

    Enum.each(old_destroyed, fn entity ->
      do_unregister_entity(entity.id)
    end)

    length(old_destroyed)
  end

  defp do_cleanup_old_entities(max_age_seconds) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -max_age_seconds, :second)

    # Get all entities and filter by criteria
    old_entities =
      :ets.select(@entities_table, [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.filter(fn {_id, entity} ->
        entity.status == :destroyed and
        DateTime.compare(entity.updated_at, cutoff_time) == :lt
      end)
      |> Enum.map(fn {id, _entity} -> id end)

    Enum.each(old_entities, &do_unregister_entity/1)

    length(old_entities)
  end

  defp do_rebuild_indexes do
    # Clear all index tables
    :ets.delete_all_objects(@status_index)
    :ets.delete_all_objects(@archetype_index)
    :ets.delete_all_objects(@parent_index)
    :ets.delete_all_objects(@tag_index)

    # Rebuild from all entities
    :ets.foldl(fn {_id, entity}, _acc ->
      update_indexes_for_entity(entity, nil)
    end, nil, @entities_table)
  end

  defp initialize_statistics do
    stats = %{
      entities_created: 0,
      entities_updated: 0,
      entities_unregistered: 0,
      queries_executed: 0,
      gc_executions: 0,
      cleanup_executions: 0,
      indexes_rebuilt: 0,
      last_updated: DateTime.utc_now()
    }

    :ets.insert(@statistics_table, {:counters, stats})
  end

  defp update_statistics(event) do
    case :ets.lookup(@statistics_table, :counters) do
      [{:counters, stats}] ->
        updated_stats = increment_stat(stats, event)
          |> Map.put(:last_updated, DateTime.utc_now())

        :ets.insert(@statistics_table, {:counters, updated_stats})

      [] -> initialize_statistics()
    end
  end

  defp increment_stat(stats, :entity_created), do: Map.update!(stats, :entities_created, &(&1 + 1))
  defp increment_stat(stats, :entity_updated), do: Map.update!(stats, :entities_updated, &(&1 + 1))
  defp increment_stat(stats, :entity_unregistered), do: Map.update!(stats, :entities_unregistered, &(&1 + 1))
  defp increment_stat(stats, :query_executed), do: Map.update!(stats, :queries_executed, &(&1 + 1))
  defp increment_stat(stats, :gc_executed), do: Map.update!(stats, :gc_executions, &(&1 + 1))
  defp increment_stat(stats, :cleanup_executed), do: Map.update!(stats, :cleanup_executions, &(&1 + 1))
  defp increment_stat(stats, :indexes_rebuilt), do: Map.update!(stats, :indexes_rebuilt, &(&1 + 1))

  defp update_periodic_statistics do
    current_stats = %{
      total_entities: total_count(),
      status_distribution: count_by_status(),
      archetype_distribution: count_by_archetype(),
      memory_usage: memory_usage(),
      timestamp: DateTime.utc_now()
    }

    :ets.insert(@statistics_table, {:current, current_stats})
  end

  defp compile_statistics do
    counters = case :ets.lookup(@statistics_table, :counters) do
      [{:counters, stats}] -> stats
      [] -> %{}
    end

    _current = case :ets.lookup(@statistics_table, :current) do
      [{:current, stats}] -> stats
      [] -> %{}
    end

    # Always update current stats when requested
    update_periodic_statistics()

    current_updated = case :ets.lookup(@statistics_table, :current) do
      [{:current, stats}] -> stats
      [] -> %{}
    end

    Map.merge(counters, current_updated)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :periodic_cleanup, 300_000)  # 5 minutes
  end

  defp schedule_statistics_update do
    Process.send_after(self(), :update_statistics, 60_000)  # 1 minute
  end
end
