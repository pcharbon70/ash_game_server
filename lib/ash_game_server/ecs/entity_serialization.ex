defmodule AshGameServer.ECS.EntitySerialization do
  @moduledoc """
  Entity Serialization system for the ECS architecture.

  Provides comprehensive serialization and persistence with:
  - Export/import entities with all components and relationships
  - Version management and migration support
  - Batch operations for performance
  - Compression and optimization
  - Format support (JSON, binary, custom)
  """

  alias AshGameServer.ECS.Entity
  alias AshGameServer.ECS.EntityRegistry
  alias AshGameServer.ECS.EntityRelationships
  alias AshGameServer.Storage

  @type entity_id :: Entity.entity_id()
  @type serialization_format :: :json | :binary | :compressed
  @type export_options :: %{
    format: serialization_format(),
    include_components: boolean(),
    include_relationships: boolean(),
    include_metadata: boolean(),
    compression: boolean(),
    version: String.t()
  }

  @type import_options :: %{
    format: serialization_format(),
    merge_strategy: :replace | :merge | :skip_existing,
    validate: boolean(),
    migrate: boolean()
  }

  @type serialized_entity :: %{
    entity: map(),
    components: map(),
    relationships: [map()],
    metadata: map(),
    version: String.t(),
    exported_at: DateTime.t()
  }

  @type export_result :: %{
    entities: [serialized_entity()],
    metadata: map(),
    version: String.t(),
    exported_at: DateTime.t(),
    format: serialization_format()
  }

  @current_version "1.0.0"

  # Export Operations

  @doc """
  Export a single entity with all its data.
  """
  @spec export_entity(entity_id(), export_options()) ::
    {:ok, serialized_entity()} | {:error, term()}
  def export_entity(entity_id, opts \\ %{}) do
    with {:ok, entity} <- EntityRegistry.get_entity(entity_id) do
      serialized = build_serialized_entity(entity, opts)
      {:ok, serialized}
    end
  end

  @doc """
  Export multiple entities efficiently.
  """
  @spec export_entities([entity_id()], export_options()) ::
    {:ok, export_result()} | {:error, term()}
  def export_entities(entity_ids, opts \\ %{}) do
    format = Map.get(opts, :format, :json)

    serialized_entities =
      entity_ids
      |> Enum.map(&export_entity(&1, opts))
      |> Enum.filter(&(elem(&1, 0) == :ok))
      |> Enum.map(&elem(&1, 1))

    result = %{
      entities: serialized_entities,
      metadata: %{
        entity_count: length(serialized_entities),
        export_options: opts
      },
      version: @current_version,
      exported_at: DateTime.utc_now(),
      format: format
    }

    formatted_result = case format do
      :json -> {:ok, Jason.encode!(result)}
      :binary -> {:ok, :erlang.term_to_binary(result)}
      :compressed -> {:ok, :erlang.term_to_binary(result, [:compressed])}
    end

    formatted_result
  end

  @doc """
  Export entities by archetype.
  """
  @spec export_by_archetype(Entity.archetype_name(), export_options()) ::
    {:ok, export_result()} | {:error, term()}
  def export_by_archetype(archetype_name, opts \\ %{}) do
    entity_ids = EntityRegistry.query_by_archetype(archetype_name)
    export_entities(entity_ids, opts)
  end

  @doc """
  Export entities by query filters.
  """
  @spec export_by_query(map(), export_options()) ::
    {:ok, export_result()} | {:error, term()}
  def export_by_query(filters, opts \\ %{}) do
    entities = EntityRegistry.query_entities(filters)
    entity_ids = Enum.map(entities, & &1.id)
    export_entities(entity_ids, opts)
  end

  @doc """
  Export entity hierarchy (entity with all descendants).
  """
  @spec export_hierarchy(entity_id(), export_options()) ::
    {:ok, export_result()} | {:error, term()}
  def export_hierarchy(root_entity_id, opts \\ %{}) do
    descendants = EntityRelationships.get_descendants(root_entity_id)
    all_entities = [root_entity_id | descendants]
    export_entities(all_entities, opts)
  end

  # Import Operations

  @doc """
  Import a single serialized entity.
  """
  @spec import_entity(serialized_entity(), import_options()) ::
    {:ok, entity_id()} | {:error, term()}
  def import_entity(serialized_entity, opts \\ %{}) do
    merge_strategy = Map.get(opts, :merge_strategy, :replace)
    validate = Map.get(opts, :validate, true)
    migrate = Map.get(opts, :migrate, true)

    with :ok <- maybe_validate_entity(serialized_entity, validate),
         {:ok, migrated_entity} <- maybe_migrate_entity(serialized_entity, migrate),
         {:ok, entity_id} <- create_or_update_entity(migrated_entity, merge_strategy) do

      # Import components
      import_components(entity_id, migrated_entity.components, merge_strategy)

      # Import relationships (deferred to avoid ordering issues)
      schedule_relationship_import(entity_id, migrated_entity.relationships)

      {:ok, entity_id}
    end
  end

  @doc """
  Import multiple entities from export result.
  """
  @spec import_entities(export_result() | String.t(), import_options()) ::
    {:ok, [entity_id()]} | {:error, term()}
  def import_entities(export_data, opts \\ %{}) do
    format = Map.get(opts, :format, :json)

    with {:ok, parsed_data} <- parse_export_data(export_data, format),
         :ok <- validate_export_format(parsed_data),
         {:ok, migrated_data} <- maybe_migrate_export(parsed_data, opts) do

      # Import entities in dependency order
      import_results =
        migrated_data.entities
        |> sort_by_dependencies()
        |> Enum.map(&import_entity(&1, opts))

      # Check for errors
      errors = Enum.filter(import_results, &(elem(&1, 0) == :error))

      if errors == [] do
        entity_ids = Enum.map(import_results, &elem(&1, 1))

        # Import relationships after all entities are created
        import_deferred_relationships()

        {:ok, entity_ids}
      else
        {:error, {:import_errors, errors}}
      end
    end
  end

  @doc """
  Import entities with conflict resolution.
  """
  @spec import_with_merge(export_result(), import_options()) ::
    {:ok, %{created: [entity_id()], updated: [entity_id()], skipped: [entity_id()]}} | {:error, term()}
  def import_with_merge(export_data, opts \\ %{}) do
    results = %{created: [], updated: [], skipped: []}

    case import_entities(export_data, opts) do
      {:ok, entity_ids} ->
        # Categorize results based on merge strategy outcomes
        {:ok, Map.put(results, :created, entity_ids)}

      error -> error
    end
  end

  # Batch Operations

  @doc """
  Export entities in batches for large datasets.
  """
  @spec export_batch([entity_id()], pos_integer(), export_options()) ::
    Stream.t()
  def export_batch(entity_ids, batch_size, opts \\ %{}) do
    entity_ids
    |> Stream.chunk_every(batch_size)
    |> Stream.map(fn batch ->
      case export_entities(batch, opts) do
        {:ok, result} -> {:ok, result}
        error -> error
      end
    end)
  end

  @doc """
  Import entities in batches with progress tracking.
  """
  @spec import_batch(Stream.t(), import_options()) ::
    {:ok, %{total: non_neg_integer(), success: non_neg_integer(), errors: [term()]}} | {:error, term()}
  def import_batch(batch_stream, opts \\ %{}) do
    results = %{total: 0, success: 0, errors: []}
    final_results = Enum.reduce(batch_stream, results, &process_batch(&1, &2, opts))
    {:ok, final_results}
  end

  defp process_batch({:ok, export_result}, acc, opts) do
    case import_entities(export_result, opts) do
      {:ok, entity_ids} ->
        update_batch_success(acc, entity_ids)
      {:error, error} ->
        update_batch_error(acc, export_result, error)
    end
  end

  defp process_batch({:error, error}, acc, _opts) do
    %{acc | errors: [error | acc.errors]}
  end

  defp update_batch_success(acc, entity_ids) do
    %{acc |
      total: acc.total + length(entity_ids),
      success: acc.success + length(entity_ids)
    }
  end

  defp update_batch_error(acc, export_result, error) do
    %{acc |
      total: acc.total + length(export_result.entities),
      errors: [error | acc.errors]
    }
  end

  # Versioning and Migration

  @doc """
  Get the current serialization version.
  """
  @spec current_version() :: String.t()
  def current_version, do: @current_version

  @doc """
  Check if migration is needed for serialized data.
  """
  @spec migration_needed?(String.t()) :: boolean()
  def migration_needed?(version) do
    Version.compare(version, @current_version) == :lt
  end

  @doc """
  Migrate serialized entity to current version.
  """
  @spec migrate_entity(serialized_entity()) :: {:ok, serialized_entity()} | {:error, term()}
  def migrate_entity(serialized_entity) do
    case serialized_entity.version do
      @current_version -> {:ok, serialized_entity}
      old_version -> perform_migration(serialized_entity, old_version, @current_version)
    end
  end

  # Validation

  @doc """
  Validate a serialized entity structure.
  """
  @spec validate_serialized_entity(serialized_entity()) :: :ok | {:error, term()}
  def validate_serialized_entity(serialized_entity) do
    required_fields = [:entity, :components, :version, :exported_at]

    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(serialized_entity, field)
    end)

    if missing_fields == [] do
      validate_entity_structure(serialized_entity.entity)
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  # Utilities

  @doc """
  Get export statistics for analysis.
  """
  @spec get_export_stats(export_result()) :: map()
  def get_export_stats(export_result) do
    entities = export_result.entities

    %{
      entity_count: length(entities),
      component_types: get_unique_component_types(entities),
      relationship_count: count_total_relationships(entities),
      archetype_distribution: get_archetype_distribution(entities),
      data_size: estimate_data_size(export_result),
      export_date: export_result.exported_at
    }
  end

  @doc """
  Optimize serialized data for storage.
  """
  @spec optimize_export(export_result()) :: export_result()
  def optimize_export(export_result) do
    optimized_entities = Enum.map(export_result.entities, &optimize_entity/1)

    %{export_result |
      entities: optimized_entities,
      metadata: Map.put(export_result.metadata, :optimized, true)
    }
  end

  # Private Functions

  defp build_serialized_entity(entity, opts) do
    include_components = Map.get(opts, :include_components, true)
    include_relationships = Map.get(opts, :include_relationships, true)
    include_metadata = Map.get(opts, :include_metadata, true)

    components = if include_components do
      case Storage.get_components(entity.id) do
        {:ok, comp_data} -> comp_data
        _ -> %{}
      end
    else
      %{}
    end

    relationships = if include_relationships do
      EntityRelationships.get_relationships(entity.id)
    else
      []
    end

    metadata = if include_metadata do
      %{
        archetype: entity.archetype,
        tags: entity.tags,
        created_at: entity.created_at,
        updated_at: entity.updated_at
      }
    else
      %{}
    end

    %{
      entity: entity,
      components: components,
      relationships: relationships,
      metadata: metadata,
      version: @current_version,
      exported_at: DateTime.utc_now()
    }
  end

  defp parse_export_data(data, format) do
    case format do
      :json -> Jason.decode(data, keys: :atoms)
      :binary -> {:ok, :erlang.binary_to_term(data)}
      :compressed -> {:ok, :erlang.binary_to_term(data)}
    end
  end

  defp validate_export_format(data) do
    required_fields = [:entities, :version, :exported_at, :format]

    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(data, field)
    end)

    if missing_fields == [] do
      :ok
    else
      {:error, {:invalid_export_format, missing_fields}}
    end
  end

  defp maybe_validate_entity(entity, true), do: validate_serialized_entity(entity)
  defp maybe_validate_entity(_entity, false), do: :ok

  defp maybe_migrate_entity(entity, true), do: migrate_entity(entity)
  defp maybe_migrate_entity(entity, false), do: {:ok, entity}

  defp maybe_migrate_export(export_data, opts) do
    migrate = Map.get(opts, :migrate, true)

    if migrate and migration_needed?(export_data.version) do
      migrated_entities = Enum.map(export_data.entities, fn entity ->
        {:ok, migrated} = migrate_entity(entity)
        migrated
      end)

      {:ok, %{export_data | entities: migrated_entities, version: @current_version}}
    else
      {:ok, export_data}
    end
  end

  defp create_or_update_entity(serialized_entity, merge_strategy) do
    entity_data = serialized_entity.entity
    entity_id = entity_data.id

    case EntityRegistry.exists?(entity_id) do
      true ->
        case merge_strategy do
          :skip_existing -> {:ok, entity_id}
          :replace ->
            Entity.update(entity_id, Map.to_list(entity_data))
            {:ok, entity_id}
          :merge ->
            Entity.update(entity_id, Map.to_list(entity_data))
            {:ok, entity_id}
        end

      false ->
        # Create new entity
        case Entity.create(id: entity_id, archetype: entity_data.archetype) do
          {:ok, entity} -> {:ok, entity.id}
          error -> error
        end
    end
  end

  defp import_components(entity_id, components, merge_strategy) do
    Enum.each(components, fn {component_name, component_data} ->
      import_single_component(entity_id, component_name, component_data, merge_strategy)
    end)
  end

  defp import_single_component(entity_id, component_name, component_data, :replace) do
    Storage.add_component(entity_id, component_name, component_data)
  end

  defp import_single_component(entity_id, component_name, component_data, :merge) do
    case Storage.get_component(entity_id, component_name) do
      {:ok, existing_data} ->
        merged_data = Map.merge(existing_data, component_data)
        Storage.add_component(entity_id, component_name, merged_data)
      {:error, :not_found} ->
        Storage.add_component(entity_id, component_name, component_data)
    end
  end

  defp import_single_component(entity_id, component_name, component_data, :skip_existing) do
    case Storage.get_component(entity_id, component_name) do
      {:error, :not_found} ->
        Storage.add_component(entity_id, component_name, component_data)
      _ -> :ok
    end
  end

  defp schedule_relationship_import(entity_id, relationships) do
    # Store relationships for deferred import
    :ets.insert_new(:deferred_relationships, {entity_id, relationships})
  end

  defp import_deferred_relationships do
    # Import all deferred relationships
    :ets.foldl(fn {_entity_id, relationships}, _acc ->
      Enum.each(relationships, fn relationship ->
        EntityRelationships.create_relationship(
          relationship.from_entity,
          relationship.to_entity,
          relationship.type,
          relationship.metadata
        )
      end)
    end, nil, :deferred_relationships)

    # Clear deferred relationships
    :ets.delete_all_objects(:deferred_relationships)
  end

  defp sort_by_dependencies(entities) do
    # Sort entities so parents come before children
    Enum.sort_by(entities, fn entity ->
      parent_id = get_in(entity, [:entity, :parent_id])
      if parent_id, do: 1, else: 0
    end)
  end

  defp validate_entity_structure(entity) do
    required_fields = [:id, :version, :created_at]

    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(entity, field)
    end)

    if missing_fields == [] do
      :ok
    else
      {:error, {:invalid_entity_structure, missing_fields}}
    end
  end

  defp perform_migration(entity, from_version, to_version) do
    # Simple migration logic - in a real system this would be more sophisticated
    case {from_version, to_version} do
      {"0.9.0", "1.0.0"} ->
        # Example migration: add new fields with defaults
        migrated_entity = %{entity |
          version: to_version,
          entity: Map.put_new(entity.entity, :migration_notes, "Migrated from #{from_version}")
        }
        {:ok, migrated_entity}

      _ ->
        {:error, {:unsupported_migration, from_version, to_version}}
    end
  end

  defp get_unique_component_types(entities) do
    entities
    |> Enum.flat_map(fn entity -> Map.keys(entity.components) end)
    |> Enum.uniq()
  end

  defp count_total_relationships(entities) do
    entities
    |> Enum.map(fn entity -> length(entity.relationships) end)
    |> Enum.sum()
  end

  defp get_archetype_distribution(entities) do
    entities
    |> Enum.group_by(fn entity -> get_in(entity, [:entity, :archetype]) end)
    |> Enum.map(fn {archetype, entities} -> {archetype, length(entities)} end)
    |> Enum.into(%{})
  end

  defp estimate_data_size(export_result) do
    # Rough estimate of serialized data size
    :erlang.external_size(export_result)
  end

  defp optimize_entity(entity) do
    # Remove nil values and empty collections
    optimized_components =
      entity.components
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == %{} or value == [] end)
      |> Enum.into(%{})

    %{entity | components: optimized_components}
  end
end
