defmodule AshGameServer.ECS.ComponentTools do
  @moduledoc """
  Development and debugging tools for component management.
  
  Provides utilities for:
  - Component inspection and debugging
  - Performance profiling and analysis
  - Memory usage monitoring
  - Data validation and migration
  - Development workflows
  """
  
  alias AshGameServer.ECS.{ComponentRegistry, EnhancedStorage, ComponentQuery, ComponentEvents}
  alias AshGameServer.Storage
  
  @type entity_id :: term()
  @type component_name :: atom()
  @type profiling_result :: map()
  @type validation_report :: map()
  
  # Component Inspector
  
  @doc """
  Inspects a component instance with detailed information.
  """
  @spec inspect_component(entity_id(), component_name()) :: map()
  def inspect_component(entity_id, component_name) do
    case EnhancedStorage.get_component(entity_id, component_name) do
      {:ok, data} ->
        metadata = case ComponentRegistry.get_component(component_name) do
          {:ok, meta} -> meta
          _ -> %{}
        end
        
        %{
          entity_id: entity_id,
          component: component_name,
          data: data,
          metadata: metadata,
          size: :erts_debug.size(data),
          memory_words: :erts_debug.flat_size(data),
          validation: validate_component_data(component_name, data),
          recent_events: get_recent_events(entity_id, component_name),
          storage_stats: EnhancedStorage.get_component_stats(component_name)
        }
      
      error -> %{error: error}
    end
  end
  
  @doc """
  Inspects all components on an entity.
  """
  @spec inspect_entity(entity_id()) :: map()
  def inspect_entity(entity_id) do
    case Storage.get_components(entity_id) do
      {:ok, components} ->
        component_details = Enum.map(components, fn {name, _data} ->
          {name, inspect_component(entity_id, name)}
        end) |> Enum.into(%{})
        
        %{
          entity_id: entity_id,
          component_count: map_size(components),
          components: component_details,
          total_memory: calculate_entity_memory(components),
          archetype: determine_archetype(Map.keys(components))
        }
      
      error -> %{error: error}
    end
  end
  
  @doc """
  Shows a summary of all registered components.
  """
  @spec list_components() :: [map()]
  def list_components do
    ComponentRegistry.list_components()
    |> Enum.map(fn metadata ->
      stats = EnhancedStorage.get_component_stats(metadata.name)
      
      Map.merge(metadata, %{
        instance_count: count_component_instances(metadata.name),
        storage_stats: stats,
        memory_usage: estimate_component_memory(metadata.name)
      })
    end)
  end
  
  # Performance Profiler
  
  @doc """
  Profiles component operations over a time period.
  """
  @spec profile_component(component_name(), pos_integer()) :: profiling_result()
  def profile_component(component_name, duration_ms \\ 5000) do
    start_time = System.monotonic_time()
    start_stats = EnhancedStorage.get_component_stats(component_name)
    
    # Wait for the specified duration
    Process.sleep(duration_ms)
    
    end_time = System.monotonic_time()
    end_stats = EnhancedStorage.get_component_stats(component_name)
    
    # Calculate metrics
    duration_seconds = (end_time - start_time) / :timer.seconds(1)
    
    %{
      component: component_name,
      duration_seconds: duration_seconds,
      operations: %{
        reads: end_stats.read_count - start_stats.read_count,
        writes: end_stats.write_count - start_stats.write_count
      },
      performance: %{
        reads_per_second: (end_stats.read_count - start_stats.read_count) / duration_seconds,
        writes_per_second: (end_stats.write_count - start_stats.write_count) / duration_seconds,
        avg_read_time: calculate_average_time(end_stats, start_stats, :read),
        avg_write_time: calculate_average_time(end_stats, start_stats, :write)
      },
      memory_usage: estimate_component_memory(component_name),
      recommendations: generate_performance_recommendations(component_name, end_stats)
    }
  end
  
  @doc """
  Profiles a specific query operation.
  """
  @spec profile_query(ComponentQuery.t()) :: map()
  def profile_query(query) do
    {time, result} = :timer.tc(fn ->
      ComponentQuery.execute(query)
    end)
    
    %{
      query: query,
      execution_time_microseconds: time,
      execution_time_ms: time / 1000,
      result_count: case result do
        {:ok, results} -> length(results)
        _ -> 0
      end,
      performance_grade: grade_query_performance(time),
      optimization_suggestions: suggest_query_optimizations(query, time)
    }
  end
  
  @doc """
  Runs a benchmark comparing different query approaches.
  """
  @spec benchmark_queries([ComponentQuery.t()], pos_integer()) :: map()
  def benchmark_queries(queries, iterations \\ 100) do
    results = Enum.map(queries, fn query ->
      times = for _ <- 1..iterations do
        {time, _result} = :timer.tc(fn ->
          ComponentQuery.execute(query)
        end)
        time
      end
      
      avg_time = Enum.sum(times) / length(times)
      min_time = Enum.min(times)
      max_time = Enum.max(times)
      
      %{
        query: query,
        iterations: iterations,
        avg_time_microseconds: avg_time,
        min_time_microseconds: min_time,
        max_time_microseconds: max_time,
        std_deviation: calculate_std_deviation(times, avg_time)
      }
    end)
    
    %{
      benchmark_results: results,
      fastest_query: Enum.min_by(results, & &1.avg_time_microseconds),
      slowest_query: Enum.max_by(results, & &1.avg_time_microseconds)
    }
  end
  
  # Memory Analyzer
  
  @doc """
  Analyzes memory usage across all components.
  """
  @spec analyze_memory() :: map()
  def analyze_memory do
    components = ComponentRegistry.list_components()
    
    component_memory = Enum.map(components, fn metadata ->
      memory = estimate_component_memory(metadata.name)
      instance_count = count_component_instances(metadata.name)
      
      %{
        component: metadata.name,
        total_memory_bytes: memory,
        instance_count: instance_count,
        avg_memory_per_instance: if(instance_count > 0, do: memory / instance_count, else: 0),
        memory_percentage: 0  # Will be calculated below
      }
    end)
    
    total_memory = Enum.sum(Enum.map(component_memory, & &1.total_memory_bytes))
    
    # Calculate percentages
    component_memory_with_percentages = Enum.map(component_memory, fn comp ->
      percentage = if total_memory > 0, do: comp.total_memory_bytes / total_memory * 100, else: 0
      Map.put(comp, :memory_percentage, percentage)
    end)
    
    %{
      total_memory_bytes: total_memory,
      total_memory_mb: total_memory / (1024 * 1024),
      component_breakdown: component_memory_with_percentages,
      top_memory_consumers: Enum.sort_by(component_memory_with_percentages, & &1.total_memory_bytes, :desc) |> Enum.take(5),
      memory_recommendations: generate_memory_recommendations(component_memory_with_percentages)
    }
  end
  
  @doc """
  Tracks memory usage over time.
  """
  @spec start_memory_tracking(pos_integer()) :: :ok
  def start_memory_tracking(interval_ms \\ 10_000) do
    spawn(fn ->
      memory_tracking_loop(interval_ms)
    end)
    :ok
  end
  
  # Validation Tools
  
  @doc """
  Validates all instances of a component type.
  """
  @spec validate_component_instances(component_name()) :: validation_report()
  def validate_component_instances(component_name) do
    # Get all entities with this component
    entities = Storage.query_entities([component_name])
    
    validation_results = Enum.map(entities, fn entity_id ->
      case EnhancedStorage.get_component(entity_id, component_name) do
        {:ok, data} ->
          validation_result = validate_component_data(component_name, data)
          %{entity_id: entity_id, validation: validation_result}
        error ->
          %{entity_id: entity_id, validation: {:error, error}}
      end
    end)
    
    errors = Enum.filter(validation_results, fn result ->
      case result.validation do
        :ok -> false
        _ -> true
      end
    end)
    
    %{
      component: component_name,
      total_instances: length(validation_results),
      valid_instances: length(validation_results) - length(errors),
      invalid_instances: length(errors),
      errors: errors,
      validation_rate: (length(validation_results) - length(errors)) / length(validation_results) * 100
    }
  end
  
  @doc """
  Migrates component data to a new version.
  """
  @spec migrate_component_data(component_name(), non_neg_integer()) :: map()
  def migrate_component_data(component_name, from_version) do
    if ComponentRegistry.can_migrate?(component_name, from_version, from_version + 1) do
      entities = Storage.query_entities([component_name])
      
      migration_results = Enum.map(entities, fn entity_id ->
        migrate_single_entity(entity_id, component_name, from_version)
      end)
      
      successful = Enum.count(migration_results, & &1.status == :success)
      
      %{
        component: component_name,
        from_version: from_version,
        to_version: from_version + 1,
        total_entities: length(migration_results),
        successful_migrations: successful,
        failed_migrations: length(migration_results) - successful,
        migration_rate: successful / length(migration_results) * 100,
        details: migration_results
      }
    else
      %{error: :migration_not_supported}
    end
  end
  
  # Private Helper Functions

  defp migrate_single_entity(entity_id, component_name, from_version) do
    case EnhancedStorage.get_component(entity_id, component_name) do
      {:ok, data} ->
        case ComponentRegistry.migrate_component(component_name, data, from_version) do
          {:ok, migrated_data} ->
            EnhancedStorage.update_component(entity_id, component_name, migrated_data)
            %{entity_id: entity_id, status: :success}
          error ->
            %{entity_id: entity_id, status: :error, error: error}
        end
      error ->
        %{entity_id: entity_id, status: :error, error: error}
    end
  end
  
  defp validate_component_data(component_name, data) do
    case ComponentRegistry.get_component(component_name) do
      {:ok, metadata} ->
        module = Map.get(metadata, :module)
        if function_exported?(module, :validate, 1) do
          module.validate(data)
        else
          :ok
        end
      _ -> {:error, :component_not_registered}
    end
  end
  
  defp get_recent_events(entity_id, component_name) do
    ComponentEvents.get_event_history(entity_id, component_name, limit: 5)
  end
  
  defp calculate_entity_memory(components) do
    Enum.reduce(components, 0, fn {_name, data}, acc ->
      acc + :erts_debug.size(data) * 8  # Approximate bytes
    end)
  end
  
  defp determine_archetype(component_names) do
    # This would match against known archetypes
    # For now, just return the component list
    component_names
  end
  
  defp count_component_instances(component_name) do
    length(Storage.query_entities([component_name]))
  end
  
  defp estimate_component_memory(component_name) do
    entities = Storage.query_entities([component_name])
    
    sample_size = min(100, length(entities))
    sample_entities = Enum.take_random(entities, sample_size)
    
    sample_memory = Enum.reduce(sample_entities, 0, fn entity_id, acc ->
      case EnhancedStorage.get_component(entity_id, component_name) do
        {:ok, data} -> acc + :erts_debug.size(data) * 8
        _ -> acc
      end
    end)
    
    if sample_size > 0 do
      avg_memory = sample_memory / sample_size
      avg_memory * length(entities)
    else
      0
    end
  end
  
  defp calculate_average_time(end_stats, start_stats, operation) do
    case operation do
      :read ->
        time_diff = end_stats.total_read_time - start_stats.total_read_time
        count_diff = end_stats.read_count - start_stats.read_count
        if count_diff > 0, do: time_diff / count_diff, else: 0
      :write ->
        time_diff = end_stats.total_write_time - start_stats.total_write_time
        count_diff = end_stats.write_count - start_stats.write_count
        if count_diff > 0, do: time_diff / count_diff, else: 0
    end
  end
  
  defp generate_performance_recommendations(_component_name, stats) do
    recommendations = []
    
    # Check read/write ratio
    recommendations = if stats.read_count > stats.write_count * 10 do
      ["Consider adding more indexes for read optimization" | recommendations]
    else
      recommendations
    end
    
    # Check average times
    recommendations = if Map.get(stats, :total_read_time, 0) / max(stats.read_count, 1) > 1000 do
      ["Read operations are slow, consider optimizing data structure" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  defp grade_query_performance(time_microseconds) do
    cond do
      time_microseconds < 1000 -> :excellent
      time_microseconds < 5000 -> :good
      time_microseconds < 10_000 -> :fair
      true -> :poor
    end
  end
  
  defp suggest_query_optimizations(query, _time) do
    suggestions = []
    
    # Check for index usage
    suggestions = if query.where != [] do
      ["Consider adding indexes for WHERE clause fields" | suggestions]
    else
      suggestions
    end
    
    # Check for joins
    suggestions = if query.joins != [] do
      ["Consider denormalizing data to avoid joins" | suggestions]
    else
      suggestions
    end
    
    suggestions
  end
  
  defp calculate_std_deviation(values, mean) do
    variance = Enum.reduce(values, 0, fn value, acc ->
      acc + :math.pow(value - mean, 2)
    end) / length(values)
    
    :math.sqrt(variance)
  end
  
  defp generate_memory_recommendations(component_memory) do
    recommendations = []
    
    # Find components using excessive memory
    high_memory_components = Enum.filter(component_memory, & &1.memory_percentage > 20)
    
    recommendations = if high_memory_components != [] do
      component_names = Enum.map(high_memory_components, & &1.component)
      ["High memory usage in components: #{inspect(component_names)}" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  defp memory_tracking_loop(interval_ms) do
    memory_data = analyze_memory()
    
    # Log or store memory data
    require Logger
    Logger.info("Memory usage: #{memory_data.total_memory_mb} MB")
    
    Process.sleep(interval_ms)
    memory_tracking_loop(interval_ms)
  end
end