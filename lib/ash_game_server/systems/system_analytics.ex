defmodule AshGameServer.Systems.SystemAnalytics do
  @moduledoc """
  Analytics and performance monitoring for ECS systems.

  Features:
  - Real-time performance metrics
  - System execution profiling
  - Resource usage tracking
  - Telemetry integration
  - Performance anomaly detection
  """

  use GenServer
  require Logger

  @telemetry_prefix [:ash_game_server, :systems]

  @type metric_name :: atom()
  @type metric_value :: number()
  @type system_id :: atom() | module()

  @type metrics :: %{
    system_id() => %{
      execution_times: [float()],
      entity_counts: [non_neg_integer()],
      error_count: non_neg_integer(),
      last_execution: DateTime.t() | nil,
      average_time: float(),
      max_time: float(),
      min_time: float()
    }
  }

  @type state :: %{
    metrics: metrics(),
    sampling_rate: pos_integer(),
    retention_period: pos_integer(),
    anomaly_threshold: float(),
    telemetry_enabled: boolean()
  }

  # Client API

  @doc """
  Start the analytics service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record system execution metrics.
  """
  def record_execution(system_id, execution_time, entity_count, success? \\ true) do
    GenServer.cast(__MODULE__, {:record_execution, system_id, execution_time, entity_count, success?})
  end

  @doc """
  Get metrics for a specific system.
  """
  def get_system_metrics(system_id) do
    GenServer.call(__MODULE__, {:get_system_metrics, system_id})
  end

  @doc """
  Get all system metrics.
  """
  def get_all_metrics do
    GenServer.call(__MODULE__, :get_all_metrics)
  end

  @doc """
  Get performance summary.
  """
  def get_summary do
    GenServer.call(__MODULE__, :get_summary)
  end

  @doc """
  Reset metrics for a system.
  """
  def reset_metrics(system_id \\ :all) do
    GenServer.call(__MODULE__, {:reset_metrics, system_id})
  end

  @doc """
  Enable or disable telemetry reporting.
  """
  def set_telemetry(enabled) when is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set_telemetry, enabled})
  end

  @doc """
  Check for performance anomalies.
  """
  def check_anomalies do
    GenServer.call(__MODULE__, :check_anomalies)
  end

  @doc """
  Export metrics to a file.
  """
  def export_metrics(filepath) do
    GenServer.call(__MODULE__, {:export_metrics, filepath})
  end

  # Telemetry Events

  @doc """
  Attach telemetry handlers for system events.
  """
  def attach_telemetry_handlers do
    events = [
      @telemetry_prefix ++ [:execution, :start],
      @telemetry_prefix ++ [:execution, :stop],
      @telemetry_prefix ++ [:execution, :exception],
      @telemetry_prefix ++ [:scheduler, :tick],
      @telemetry_prefix ++ [:pipeline, :stage, :start],
      @telemetry_prefix ++ [:pipeline, :stage, :stop]
    ]

    :telemetry.attach_many(
      "ash-game-server-systems",
      events,
      &handle_telemetry_event/4,
      nil
    )
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      metrics: %{},
      sampling_rate: Keyword.get(opts, :sampling_rate, 100),
      retention_period: Keyword.get(opts, :retention_period, 1000),
      anomaly_threshold: Keyword.get(opts, :anomaly_threshold, 2.0),
      telemetry_enabled: Keyword.get(opts, :telemetry_enabled, true)
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_old_metrics, 60_000)

    # Attach telemetry handlers
    if state.telemetry_enabled do
      attach_telemetry_handlers()
    end

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_execution, system_id, execution_time, entity_count, success?}, state) do
    metrics = Map.get(state.metrics, system_id, create_empty_metrics())

    # Update metrics
    updated_metrics = update_system_metrics(metrics, execution_time, entity_count, success?)

    # Check for anomalies
    if detect_anomaly?(updated_metrics, execution_time, state.anomaly_threshold) do
      Logger.warning("Performance anomaly detected for system #{inspect(system_id)}: #{execution_time}ms")
      emit_anomaly_event(system_id, execution_time, updated_metrics.average_time)
    end

    # Emit telemetry if enabled
    if state.telemetry_enabled do
      emit_telemetry(system_id, execution_time, entity_count, success?)
    end

    new_metrics = Map.put(state.metrics, system_id, updated_metrics)
    {:noreply, %{state | metrics: new_metrics}}
  end

  @impl true
  def handle_call({:get_system_metrics, system_id}, _from, state) do
    metrics = Map.get(state.metrics, system_id, create_empty_metrics())
    {:reply, {:ok, format_metrics(metrics)}, state}
  end

  @impl true
  def handle_call(:get_all_metrics, _from, state) do
    formatted = Enum.map(state.metrics, fn {system_id, metrics} ->
      {system_id, format_metrics(metrics)}
    end)

    {:reply, {:ok, Map.new(formatted)}, state}
  end

  @impl true
  def handle_call(:get_summary, _from, state) do
    summary = generate_summary(state.metrics)
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_call({:reset_metrics, :all}, _from, state) do
    {:reply, :ok, %{state | metrics: %{}}}
  end

  @impl true
  def handle_call({:reset_metrics, system_id}, _from, state) do
    new_metrics = Map.delete(state.metrics, system_id)
    {:reply, :ok, %{state | metrics: new_metrics}}
  end

  @impl true
  def handle_call({:set_telemetry, enabled}, _from, state) do
    if enabled and not state.telemetry_enabled do
      attach_telemetry_handlers()
    end

    {:reply, :ok, %{state | telemetry_enabled: enabled}}
  end

  @impl true
  def handle_call(:check_anomalies, _from, state) do
    anomalies = detect_all_anomalies(state.metrics, state.anomaly_threshold)
    {:reply, {:ok, anomalies}, state}
  end

  @impl true
  def handle_call({:export_metrics, filepath}, _from, state) do
    result = export_metrics_to_file(state.metrics, filepath)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup_old_metrics, state) do
    new_metrics = cleanup_metrics(state.metrics, state.retention_period)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_metrics, 60_000)

    {:noreply, %{state | metrics: new_metrics}}
  end

  # Private Functions

  defp create_empty_metrics do
    %{
      execution_times: [],
      entity_counts: [],
      error_count: 0,
      last_execution: nil,
      average_time: 0.0,
      max_time: 0.0,
      min_time: Float.max_finite()
    }
  end

  defp update_system_metrics(metrics, execution_time, entity_count, success?) do
    # Add new data points
    execution_times = [execution_time | metrics.execution_times]
    entity_counts = [entity_count | metrics.entity_counts]

    # Update error count
    error_count = if success? do
      metrics.error_count
    else
      metrics.error_count + 1
    end

    # Calculate statistics
    avg_time = calculate_average(execution_times)
    max_time = Enum.max([execution_time | [metrics.max_time]], fn -> 0.0 end)
    min_time = Enum.min([execution_time | [metrics.min_time]], fn -> Float.max_finite() end)

    %{metrics |
      execution_times: Enum.take(execution_times, 100),  # Keep last 100
      entity_counts: Enum.take(entity_counts, 100),
      error_count: error_count,
      last_execution: DateTime.utc_now(),
      average_time: avg_time,
      max_time: max_time,
      min_time: min_time
    }
  end

  defp calculate_average([]), do: 0.0
  defp calculate_average(values) do
    Enum.sum(values) / length(values)
  end

  defp detect_anomaly?(metrics, execution_time, threshold) do
    if length(metrics.execution_times) > 10 do
      # Use standard deviation for anomaly detection
      std_dev = calculate_std_dev(metrics.execution_times)
      avg = metrics.average_time

      abs(execution_time - avg) > (threshold * std_dev)
    else
      false
    end
  end

  defp calculate_std_dev([]), do: 0.0
  defp calculate_std_dev(values) do
    avg = calculate_average(values)

    variance = values
    |> Enum.map(fn x -> :math.pow(x - avg, 2) end)
    |> calculate_average()

    :math.sqrt(variance)
  end

  defp detect_all_anomalies(metrics, threshold) do
    Enum.filter(metrics, fn {_system_id, system_metrics} ->
      if length(system_metrics.execution_times) > 1 do
        latest = hd(system_metrics.execution_times)
        detect_anomaly?(system_metrics, latest, threshold)
      else
        false
      end
    end)
    |> Enum.map(fn {system_id, _} -> system_id end)
  end

  defp format_metrics(metrics) do
    %{
      average_execution_time: metrics.average_time,
      max_execution_time: metrics.max_time,
      min_execution_time: if(metrics.min_time == Float.max_finite(), do: 0.0, else: metrics.min_time),
      error_count: metrics.error_count,
      last_execution: metrics.last_execution,
      recent_execution_times: Enum.take(metrics.execution_times, 10),
      average_entity_count: calculate_average(metrics.entity_counts)
    }
  end

  defp generate_summary(metrics) do
    total_systems = map_size(metrics)

    if total_systems > 0 do
      all_times = metrics
      |> Enum.flat_map(fn {_, m} -> m.execution_times end)

      total_errors = metrics
      |> Enum.map(fn {_, m} -> m.error_count end)
      |> Enum.sum()

      %{
        total_systems: total_systems,
        overall_average_time: calculate_average(all_times),
        total_errors: total_errors,
        systems_with_errors: Enum.count(metrics, fn {_, m} -> m.error_count > 0 end),
        slowest_system: find_slowest_system(metrics),
        fastest_system: find_fastest_system(metrics)
      }
    else
      %{
        total_systems: 0,
        overall_average_time: 0.0,
        total_errors: 0,
        systems_with_errors: 0,
        slowest_system: nil,
        fastest_system: nil
      }
    end
  end

  defp find_slowest_system(metrics) do
    metrics
    |> Enum.max_by(fn {_, m} -> m.average_time end, fn -> {nil, %{average_time: 0}} end)
    |> elem(0)
  end

  defp find_fastest_system(metrics) do
    metrics
    |> Enum.filter(fn {_, m} -> m.average_time > 0 end)
    |> Enum.min_by(fn {_, m} -> m.average_time end, fn -> {nil, %{average_time: 0}} end)
    |> elem(0)
  end

  defp cleanup_metrics(metrics, retention_period) do
    Enum.reduce(metrics, %{}, fn {system_id, system_metrics}, acc ->
      cleaned = %{system_metrics |
        execution_times: Enum.take(system_metrics.execution_times, retention_period),
        entity_counts: Enum.take(system_metrics.entity_counts, retention_period)
      }

      Map.put(acc, system_id, cleaned)
    end)
  end

  defp emit_telemetry(system_id, execution_time, entity_count, success?) do
    metadata = %{
      system_id: system_id,
      entity_count: entity_count,
      success: success?
    }

    measurements = %{
      execution_time: execution_time
    }

    :telemetry.execute(
      @telemetry_prefix ++ [:execution, :complete],
      measurements,
      metadata
    )
  end

  defp emit_anomaly_event(system_id, execution_time, average_time) do
    :telemetry.execute(
      @telemetry_prefix ++ [:anomaly, :detected],
      %{
        execution_time: execution_time,
        average_time: average_time,
        deviation: abs(execution_time - average_time)
      },
      %{system_id: system_id}
    )
  end

  defp export_metrics_to_file(metrics, filepath) do
    try do
      json_data = metrics
      |> Enum.map(fn {system_id, m} ->
        %{
          system_id: system_id,
          metrics: format_metrics(m)
        }
      end)
      |> Jason.encode!(pretty: true)

      File.write!(filepath, json_data)
      {:ok, filepath}
    rescue
      error ->
        {:error, error}
    end
  end

  # Telemetry Event Handler

  def handle_telemetry_event(event, measurements, metadata, _config) do
    case event do
      [@telemetry_prefix, :execution, :start] ->
        Logger.debug("System execution started: #{inspect(metadata.system_id)}")

      [@telemetry_prefix, :execution, :stop] ->
        record_execution(
          metadata.system_id,
          measurements.duration / 1_000,  # Convert to ms
          Map.get(metadata, :entity_count, 0),
          true
        )

      [@telemetry_prefix, :execution, :exception] ->
        record_execution(
          metadata.system_id,
          measurements.duration / 1_000,
          0,
          false
        )

      _ ->
        :ok
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
