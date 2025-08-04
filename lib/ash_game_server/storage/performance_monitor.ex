defmodule AshGameServer.Storage.PerformanceMonitor do
  @moduledoc """
  Performance monitoring and analytics for ETS storage operations.

  This module provides:
  - Access pattern analysis
  - Memory usage tracking
  - Query performance metrics
  - Optimization recommendations
  """

  use GenServer
  require Logger

  alias AshGameServer.Storage.ComponentStorage
  alias AshGameServer.Storage.EntityManager

  @stats_table :performance_stats
  @metrics_interval 10_000  # 10 seconds
  @report_interval 60_000   # 1 minute

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a storage operation for performance tracking.
  """
  def record_operation(operation_type, component_name, duration_us) do
    GenServer.cast(__MODULE__, {:record_operation, operation_type, component_name, duration_us})
  end

  @doc """
  Get current performance metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Get performance report with recommendations.
  """
  def get_performance_report do
    GenServer.call(__MODULE__, :get_performance_report)
  end

  @doc """
  Reset all performance statistics.
  """
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    # Create performance statistics table
    :ets.new(@stats_table, [:named_table, :public, :set])

    # Initialize metrics
    schedule_metrics_collection()
    schedule_performance_report()

    state = %{
      start_time: System.monotonic_time(:millisecond),
      operation_count: 0,
      total_operations: %{},
      component_stats: %{},
      memory_samples: []
    }

    Logger.info("Performance monitoring started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_operation, operation_type, component_name, duration_us}, state) do
    # Update operation counters
    operation_key = {operation_type, component_name}

    # Store detailed metrics in ETS
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(@stats_table, {{:operation, timestamp}, %{
      type: operation_type,
      component: component_name,
      duration_us: duration_us,
      timestamp: timestamp
    }})

    # Update state counters
    new_total_ops = Map.update(state.total_operations, operation_key, 1, &(&1 + 1))
    new_component_stats = update_component_stats(state.component_stats, component_name, operation_type, duration_us)

    new_state = %{
      state |
      operation_count: state.operation_count + 1,
      total_operations: new_total_ops,
      component_stats: new_component_stats
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = generate_current_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_performance_report, _from, state) do
    report = generate_performance_report(state)
    {:reply, report, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    :ets.delete_all_objects(@stats_table)

    reset_state = %{
      state |
      operation_count: 0,
      total_operations: %{},
      component_stats: %{},
      memory_samples: []
    }

    {:reply, :ok, reset_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect system metrics
    memory_usage = collect_memory_metrics()
    new_memory_samples = [memory_usage | Enum.take(state.memory_samples, 99)]  # Keep last 100 samples

    new_state = %{state | memory_samples: new_memory_samples}

    schedule_metrics_collection()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:generate_report, state) do
    report = generate_performance_report(state)
    log_performance_report(report)

    schedule_performance_report()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp update_component_stats(component_stats, component_name, operation_type, duration_us) do
    component_key = component_name

    default_stats = %{
      operations: %{read: 0, write: 0, delete: 0, update: 0},
      total_duration: %{read: 0, write: 0, delete: 0, update: 0},
      avg_duration: %{read: 0, write: 0, delete: 0, update: 0},
      last_access: System.monotonic_time(:millisecond)
    }

    current_stats = Map.get(component_stats, component_key, default_stats)

    # Update operation count and duration
    new_op_count = current_stats.operations[operation_type] + 1
    new_total_duration = current_stats.total_duration[operation_type] + duration_us
    new_avg_duration = new_total_duration / new_op_count

    updated_stats = %{
      current_stats |
      operations: Map.put(current_stats.operations, operation_type, new_op_count),
      total_duration: Map.put(current_stats.total_duration, operation_type, new_total_duration),
      avg_duration: Map.put(current_stats.avg_duration, operation_type, new_avg_duration),
      last_access: System.monotonic_time(:millisecond)
    }

    Map.put(component_stats, component_key, updated_stats)
  end

  defp collect_memory_metrics do
    component_stats = ComponentStorage.all_component_stats()
    entity_stats = EntityManager.entity_stats()

    total_component_memory =
      component_stats
      |> Enum.map(& &1.memory)
      |> Enum.sum()

    %{
      timestamp: System.monotonic_time(:millisecond),
      total_component_memory: total_component_memory,
      entity_memory: entity_stats.memory_usage,
      total_entities: entity_stats.total_entities,
      component_count: length(component_stats)
    }
  end

  defp generate_current_metrics(state) do
    uptime_ms = System.monotonic_time(:millisecond) - state.start_time

    # Calculate operations per second
    ops_per_second = if uptime_ms > 0, do: state.operation_count * 1000 / uptime_ms, else: 0

    # Get latest memory metrics
    latest_memory = List.first(state.memory_samples) || %{}

    %{
      uptime_ms: uptime_ms,
      total_operations: state.operation_count,
      operations_per_second: ops_per_second,
      component_performance: state.component_stats,
      memory_usage: latest_memory,
      operation_breakdown: state.total_operations
    }
  end

  defp generate_performance_report(state) do
    metrics = generate_current_metrics(state)
    recommendations = generate_recommendations(state)

    %{
      timestamp: DateTime.utc_now(),
      performance_metrics: metrics,
      recommendations: recommendations,
      component_analysis: analyze_component_performance(state.component_stats),
      memory_trend: analyze_memory_trend(state.memory_samples)
    }
  end

  defp generate_recommendations(state) do
    recommendations = []

    # Check for slow components
    slow_components =
      state.component_stats
      |> Enum.filter(fn {_name, stats} ->
        Enum.any?(stats.avg_duration, fn {_op, duration} -> duration > 1000 end)  # > 1ms
      end)
      |> Enum.map(fn {name, _stats} -> name end)

    recommendations =
      if length(slow_components) > 0 do
        ["Consider optimizing slow components: #{inspect(slow_components)}" | recommendations]
      else
        recommendations
      end

    # Check memory usage
    latest_memory = List.first(state.memory_samples)
    recommendations = if latest_memory && latest_memory.total_component_memory > 100_000_000 do  # > 100MB
      ["High memory usage detected, consider data cleanup" | recommendations]
    else
      recommendations
    end

    # Check operation patterns
    read_heavy_components =
      state.component_stats
      |> Enum.filter(fn {_name, stats} ->
        total_reads = stats.operations.read
        total_writes = stats.operations.write
        total_reads > 0 && total_reads / max(total_writes, 1) > 10
      end)
      |> Enum.map(fn {name, _stats} -> name end)

    recommendations =
      if length(read_heavy_components) > 0 do
        ["Consider caching for read-heavy components: #{inspect(read_heavy_components)}" | recommendations]
      else
        recommendations
      end

    case recommendations do
      [] -> ["Performance looks good - no specific recommendations"]
      _ -> recommendations
    end
  end

  defp analyze_component_performance(component_stats) do
    component_stats
    |> Enum.map(fn {name, stats} ->
      total_ops = Enum.sum(Map.values(stats.operations))

      %{
        component: name,
        total_operations: total_ops,
        read_percentage: stats.operations.read / max(total_ops, 1) * 100,
        write_percentage: stats.operations.write / max(total_ops, 1) * 100,
        avg_read_time_us: stats.avg_duration.read,
        avg_write_time_us: stats.avg_duration.write,
        last_access_age_ms: System.monotonic_time(:millisecond) - stats.last_access
      }
    end)
    |> Enum.sort_by(& &1.total_operations, :desc)
  end

  defp analyze_memory_trend(memory_samples) do
    if length(memory_samples) < 2 do
      %{trend: :insufficient_data}
    else
      latest = List.first(memory_samples)
      oldest = List.last(memory_samples)

      memory_change = latest.total_component_memory - oldest.total_component_memory
      time_diff = latest.timestamp - oldest.timestamp

      trend = cond do
        memory_change > 1000 -> :increasing
        memory_change < -1000 -> :decreasing
        true -> :stable
      end

      %{
        trend: trend,
        change_bytes: memory_change,
        change_rate_bytes_per_ms: if(time_diff > 0, do: memory_change / time_diff, else: 0),
        current_memory: latest.total_component_memory,
        sample_count: length(memory_samples)
      }
    end
  end

  defp log_performance_report(report) do
    Logger.info("=== Storage Performance Report ===")
    Logger.info("Operations/sec: #{Float.round(report.performance_metrics.operations_per_second, 2)}")
    Logger.info("Total operations: #{report.performance_metrics.total_operations}")
    Logger.info("Memory usage: #{report.performance_metrics.memory_usage[:total_component_memory] || 0} bytes")

    if length(report.recommendations) > 0 do
      Logger.info("Recommendations:")
      Enum.each(report.recommendations, fn rec ->
        Logger.info("  - #{rec}")
      end)
    end
  end

  defp schedule_metrics_collection do
    Process.send_after(self(), :collect_metrics, @metrics_interval)
  end

  defp schedule_performance_report do
    Process.send_after(self(), :generate_report, @report_interval)
  end
end
