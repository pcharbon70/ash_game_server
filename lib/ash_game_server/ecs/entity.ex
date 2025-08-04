defmodule AshGameServer.ECS.Entity do
  import Bitwise

  @moduledoc """
  Advanced Entity management system for the ECS architecture.

  Provides comprehensive entity lifecycle management with:
  - Advanced ID generation strategies
  - Entity versioning and lifecycle tracking
  - Entity metadata and pooling
  - Performance optimization and monitoring
  """

  @type entity_id :: non_neg_integer() | String.t()
  @type entity_version :: non_neg_integer()
  @type entity_generation :: non_neg_integer()
  @type archetype_name :: atom()
  @type entity_metadata :: map()
  @type entity_status :: :active | :inactive | :pooled | :destroyed
  @type lifecycle_event :: :created | :activated | :deactivated | :pooled | :destroyed

  @type entity :: %{
    id: entity_id(),
    version: entity_version(),
    generation: entity_generation(),
    status: entity_status(),
    archetype: archetype_name() | nil,
    components: [atom()],
    metadata: entity_metadata(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    parent_id: entity_id() | nil,
    children: [entity_id()],
    tags: [atom()],
    lifecycle_events: [lifecycle_event()]
  }

  @type id_strategy :: :incremental | :uuid | :snowflake | :pooled
  @type pooling_config :: %{
    pool_size: pos_integer(),
    prealloc_count: pos_integer(),
    max_pool_size: pos_integer(),
    gc_interval: pos_integer()
  }

  # Entity ID Generation

  @doc """
  Generate a new entity ID using the specified strategy.
  """
  @spec generate_id(id_strategy()) :: entity_id()
  def generate_id(:incremental) do
    :persistent_term.get({__MODULE__, :id_counter}, 0) + 1
    |> tap(fn id -> :persistent_term.put({__MODULE__, :id_counter}, id) end)
  end

  def generate_id(:uuid) do
    Uniq.UUID.uuid4()
  end

  def generate_id(:snowflake) do
    generate_snowflake_id()
  end

  def generate_id(:pooled) do
    get_pooled_id() || generate_id(:incremental)
  end

  @doc """
  Generate a unique snowflake-style ID with timestamp, worker, and sequence.
  """
  @spec generate_snowflake_id() :: non_neg_integer()
  def generate_snowflake_id do
    # Epoch: 2020-01-01 00:00:00 UTC
    epoch = 1_577_836_800_000
    timestamp = System.system_time(:millisecond) - epoch

    # Worker ID (can be node-specific)
    worker_id = :persistent_term.get({__MODULE__, :worker_id}, 1)

    # Sequence number
    sequence = :persistent_term.get({__MODULE__, :sequence}, 0) + 1
    |> rem(4096)  # 12-bit sequence

    :persistent_term.put({__MODULE__, :sequence}, sequence)

    # Snowflake format: 41 bits timestamp + 10 bits worker + 12 bits sequence
    (timestamp <<< 22) ||| (worker_id <<< 12) ||| sequence
  end

  # Entity Lifecycle Management

  @doc """
  Create a new entity with the specified configuration.
  """
  @spec create(keyword()) :: {:ok, entity()} | {:error, term()}
  def create(opts \\ []) do
    id_strategy = Keyword.get(opts, :id_strategy, :incremental)
    entity_id = generate_id(id_strategy)

    entity = %{
      id: entity_id,
      version: 1,
      generation: 1,
      status: :active,
      archetype: Keyword.get(opts, :archetype),
      components: [],
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      parent_id: Keyword.get(opts, :parent_id),
      children: [],
      tags: Keyword.get(opts, :tags, []),
      lifecycle_events: [:created]
    }

    # Store in registry
    AshGameServer.ECS.EntityRegistry.register_entity(entity)

    {:ok, entity}
  end

  @doc """
  Update an entity's metadata or status.
  """
  @spec update(entity_id(), keyword()) :: {:ok, entity()} | {:error, term()}
  def update(entity_id, updates) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} ->
        updated_entity = apply_updates(entity, updates)
        AshGameServer.ECS.EntityRegistry.update_entity(updated_entity)
        {:ok, updated_entity}

      error -> error
    end
  end

  defp apply_updates(entity, updates) do
    Enum.reduce(updates, entity, &apply_single_update/2)
  end

  defp apply_single_update({:metadata, value}, entity) do
    %{entity |
      metadata: Map.merge(entity.metadata, value),
      updated_at: DateTime.utc_now(),
      version: entity.version + 1
    }
  end

  defp apply_single_update({:tags, value}, entity) do
    %{entity |
      tags: Enum.uniq(entity.tags ++ value),
      updated_at: DateTime.utc_now(),
      version: entity.version + 1
    }
  end

  defp apply_single_update({:status, value}, entity) do
    event = status_to_event(value)
    %{entity |
      status: value,
      updated_at: DateTime.utc_now(),
      version: entity.version + 1,
      lifecycle_events: [event | entity.lifecycle_events]
    }
  end

  defp apply_single_update({key, value}, entity) do
    %{entity |
      key => value,
      updated_at: DateTime.utc_now(),
      version: entity.version + 1
    }
  end

  @doc """
  Destroy an entity and clean up all resources.
  """
  @spec destroy(entity_id()) :: :ok | {:error, term()}
  def destroy(entity_id) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} ->
        # Destroy all children first
        Enum.each(entity.children, &destroy/1)

        # Remove from parent's children list
        if entity.parent_id do
          remove_child(entity.parent_id, entity_id)
        end

        # Remove all components
        Enum.each(entity.components, fn component_name ->
          AshGameServer.Storage.remove_component(entity_id, component_name)
        end)

        # Update status to destroyed
        destroyed_entity = %{entity |
          status: :destroyed,
          updated_at: DateTime.utc_now(),
          lifecycle_events: [:destroyed | entity.lifecycle_events]
        }

        AshGameServer.ECS.EntityRegistry.update_entity(destroyed_entity)

        # Schedule for cleanup/pooling
        schedule_cleanup(entity_id)

        :ok

      error -> error
    end
  end

  @doc """
  Activate a pooled or inactive entity.
  """
  @spec activate(entity_id(), keyword()) :: {:ok, entity()} | {:error, term()}
  def activate(entity_id, opts \\ []) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} when entity.status in [:pooled, :inactive] ->
        activated_entity = %{entity |
          status: :active,
          generation: entity.generation + 1,
          updated_at: DateTime.utc_now(),
          lifecycle_events: [:activated | entity.lifecycle_events],
          metadata: Map.merge(entity.metadata, Keyword.get(opts, :metadata, %{}))
        }

        AshGameServer.ECS.EntityRegistry.update_entity(activated_entity)
        {:ok, activated_entity}

      {:ok, entity} ->
        {:error, {:invalid_status, entity.status}}

      error -> error
    end
  end

  @doc """
  Deactivate an entity without destroying it.
  """
  @spec deactivate(entity_id()) :: {:ok, entity()} | {:error, term()}
  def deactivate(entity_id) do
    update(entity_id, status: :inactive)
  end

  # Entity Versioning

  @doc """
  Get the current version of an entity.
  """
  @spec get_version(entity_id()) :: {:ok, entity_version()} | {:error, term()}
  def get_version(entity_id) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} -> {:ok, entity.version}
      error -> error
    end
  end

  @doc """
  Check if an entity version is current.
  """
  @spec version_current?(entity_id(), entity_version()) :: boolean()
  def version_current?(entity_id, version) do
    case get_version(entity_id) do
      {:ok, current_version} -> current_version == version
      _ -> false
    end
  end

  # Entity Pooling

  @doc """
  Configure entity pooling settings.
  """
  @spec configure_pooling(pooling_config()) :: :ok
  def configure_pooling(config) do
    :persistent_term.put({__MODULE__, :pooling_config}, config)
    initialize_pool(config)
  end

  @doc """
  Get a pooled entity ID if available.
  """
  @spec get_pooled_id() :: entity_id() | nil
  def get_pooled_id do
    case :ets.lookup(:entity_pool, :available) do
      [{:available, id} | _] ->
        :ets.delete_object(:entity_pool, {:available, id})
        id
      [] -> nil
    end
  end

  @doc """
  Return an entity ID to the pool.
  """
  @spec return_to_pool(entity_id()) :: :ok
  def return_to_pool(entity_id) do
    :ets.insert(:entity_pool, {:available, entity_id})
    :ok
  end

  # Entity Metadata

  @doc """
  Set metadata for an entity.
  """
  @spec set_metadata(entity_id(), map()) :: {:ok, entity()} | {:error, term()}
  def set_metadata(entity_id, metadata) do
    update(entity_id, metadata: metadata)
  end

  @doc """
  Get metadata for an entity.
  """
  @spec get_metadata(entity_id()) :: {:ok, map()} | {:error, term()}
  def get_metadata(entity_id) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} -> {:ok, entity.metadata}
      error -> error
    end
  end

  @doc """
  Add tags to an entity.
  """
  @spec add_tags(entity_id(), [atom()]) :: {:ok, entity()} | {:error, term()}
  def add_tags(entity_id, tags) do
    update(entity_id, tags: tags)
  end

  @doc """
  Check if an entity has a specific tag.
  """
  @spec has_tag?(entity_id(), atom()) :: boolean()
  def has_tag?(entity_id, tag) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} -> tag in entity.tags
      _ -> false
    end
  end

  # Lifecycle Events

  @doc """
  Get the lifecycle events for an entity.
  """
  @spec get_lifecycle_events(entity_id()) :: {:ok, [lifecycle_event()]} | {:error, term()}
  def get_lifecycle_events(entity_id) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} -> {:ok, entity.lifecycle_events}
      error -> error
    end
  end

  # Private Functions

  defp status_to_event(:active), do: :activated
  defp status_to_event(:inactive), do: :deactivated
  defp status_to_event(:pooled), do: :pooled
  defp status_to_event(:destroyed), do: :destroyed

  defp initialize_pool(config) do
    :ets.new(:entity_pool, [:named_table, :public, :bag])

    # Pre-allocate entity IDs
    prealloc_count = Map.get(config, :prealloc_count, 100)
    Enum.each(1..prealloc_count, fn _ ->
      id = generate_id(:incremental)
      :ets.insert(:entity_pool, {:available, id})
    end)

    :ok
  end

  defp schedule_cleanup(entity_id) do
    # Schedule cleanup after a delay to allow for pooling
    Task.start(fn ->
      Process.sleep(5000)  # 5 second delay
      cleanup_destroyed_entity(entity_id)
    end)
  end

  defp cleanup_destroyed_entity(entity_id) do
    case AshGameServer.ECS.EntityRegistry.get_entity(entity_id) do
      {:ok, entity} when entity.status == :destroyed ->
        # Check if we should pool or permanently remove
        config = :persistent_term.get({__MODULE__, :pooling_config}, %{})
        max_pool_size = Map.get(config, :max_pool_size, 1000)
        current_pool_size = :ets.info(:entity_pool, :size)

        if current_pool_size < max_pool_size do
          # Reset and pool the entity
          pooled_entity = %{entity |
            status: :pooled,
            version: 1,
            generation: entity.generation + 1,
            components: [],
            metadata: %{},
            parent_id: nil,
            children: [],
            tags: [],
            lifecycle_events: [:pooled],
            updated_at: DateTime.utc_now()
          }

          AshGameServer.ECS.EntityRegistry.update_entity(pooled_entity)
          return_to_pool(entity_id)
        else
          # Permanently remove
          AshGameServer.ECS.EntityRegistry.unregister_entity(entity_id)
        end

      _ -> :ok
    end
  end

  defp remove_child(parent_id, child_id) do
    case AshGameServer.ECS.EntityRegistry.get_entity(parent_id) do
      {:ok, parent} ->
        updated_children = List.delete(parent.children, child_id)
        updated_parent = %{parent |
          children: updated_children,
          updated_at: DateTime.utc_now(),
          version: parent.version + 1
        }
        AshGameServer.ECS.EntityRegistry.update_entity(updated_parent)

      _ -> :ok
    end
  end
end
