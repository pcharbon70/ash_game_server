defmodule AshGameServer.Systems.SystemPipeline do
  @moduledoc """
  Pipeline execution framework for ECS systems with stages and data flow.

  Features:
  - Multi-stage pipeline execution
  - Data flow between stages
  - Back-pressure handling
  - Error recovery and circuit breakers
  - Parallel stage execution
  """

  use GenServer
  require Logger

  @type stage_name :: atom()
  @type stage_config :: map()
  @type pipeline_data :: map()

  @type stage :: %{
    name: stage_name(),
    systems: [module()],
    parallel: boolean(),
    timeout: pos_integer(),
    error_handler: (term() -> :retry | :skip | :halt),
    transformers: [(pipeline_data() -> pipeline_data())]
  }

  @type state :: %{
    stages: [stage()],
    current_stage: stage_name() | nil,
    pipeline_data: pipeline_data(),
    metrics: map(),
    circuit_breakers: map(),
    running: boolean()
  }

  # Client API

  @doc """
  Start a pipeline process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Define a new pipeline stage.
  """
  def add_stage(pipeline \\ __MODULE__, name, config) do
    GenServer.call(pipeline, {:add_stage, name, config})
  end

  @doc """
  Execute the pipeline with initial data.
  """
  def execute(pipeline \\ __MODULE__, initial_data \\ %{}) do
    GenServer.call(pipeline, {:execute, initial_data}, :infinity)
  end

  @doc """
  Execute a specific stage.
  """
  def execute_stage(pipeline \\ __MODULE__, stage_name, data) do
    GenServer.call(pipeline, {:execute_stage, stage_name, data})
  end

  @doc """
  Get pipeline metrics.
  """
  def get_metrics(pipeline \\ __MODULE__) do
    GenServer.call(pipeline, :get_metrics)
  end

  @doc """
  Reset circuit breakers.
  """
  def reset_circuit_breakers(pipeline \\ __MODULE__) do
    GenServer.call(pipeline, :reset_circuit_breakers)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      stages: [],
      current_stage: nil,
      pipeline_data: %{},
      metrics: %{
        executions: 0,
        failures: 0,
        stage_timings: %{},
        last_execution_time: 0
      },
      circuit_breakers: %{},
      running: false
    }

    # Load predefined stages if provided
    stages = Keyword.get(opts, :stages, [])
    state_with_stages = Enum.reduce(stages, state, fn {name, config}, acc ->
      add_stage_to_state(acc, name, config)
    end)

    {:ok, state_with_stages}
  end

  @impl true
  def handle_call({:add_stage, name, config}, _from, state) do
    new_state = add_stage_to_state(state, name, config)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:execute, initial_data}, _from, state) do
    if state.running do
      {:reply, {:error, :already_running}, state}
    else
      start_time = System.monotonic_time(:microsecond)

      # Execute pipeline
      result = execute_pipeline(state.stages, initial_data, state)

      # Update metrics
      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time

      new_metrics = update_execution_metrics(state.metrics, duration, result)
      new_state = %{state | metrics: new_metrics}

      {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call({:execute_stage, stage_name, data}, _from, state) do
    case find_stage(state.stages, stage_name) do
      nil ->
        {:reply, {:error, :stage_not_found}, state}

      stage ->
        result = execute_single_stage(stage, data, state)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call(:reset_circuit_breakers, _from, state) do
    new_state = %{state | circuit_breakers: %{}}
    {:reply, :ok, new_state}
  end

  # Private Functions

  defp add_stage_to_state(state, name, config) do
    stage = %{
      name: name,
      systems: Map.get(config, :systems, []),
      parallel: Map.get(config, :parallel, false),
      timeout: Map.get(config, :timeout, 5000),
      error_handler: Map.get(config, :error_handler, &default_error_handler/1),
      transformers: Map.get(config, :transformers, [])
    }

    # Initialize circuit breaker for this stage
    circuit_breakers = Map.put(state.circuit_breakers, name, %{
      failures: 0,
      threshold: Map.get(config, :failure_threshold, 5),
      state: :closed
    })

    %{state |
      stages: state.stages ++ [stage],
      circuit_breakers: circuit_breakers
    }
  end

  defp execute_pipeline([], data, _state), do: {:ok, data}
  defp execute_pipeline([stage | rest], data, state) do
    # Check circuit breaker
    case check_circuit_breaker(state.circuit_breakers, stage.name) do
      :open ->
        Logger.warning("Circuit breaker open for stage #{stage.name}, skipping")
        execute_pipeline(rest, data, state)

      :closed ->
        case execute_single_stage(stage, data, state) do
          {:ok, new_data} ->
            # Reset circuit breaker on success
            reset_stage_circuit_breaker(state, stage.name)
            execute_pipeline(rest, new_data, state)

          {:error, reason} = error ->
            # Trip circuit breaker on failure
            trip_stage_circuit_breaker(state, stage.name)

            # Handle error
            handle_stage_error(stage, rest, data, state, reason, error)
        end
    end
  end

  defp handle_stage_error(stage, rest, data, state, reason, error) do
    case stage.error_handler.(reason) do
      :retry ->
        execute_pipeline([stage | rest], data, state)

      :skip ->
        Logger.warning("Skipping stage #{stage.name} due to error: #{inspect(reason)}")
        execute_pipeline(rest, data, state)

      :halt ->
        error
    end
  end

  defp execute_single_stage(stage, data, state) do
    Logger.debug("Executing stage: #{stage.name}")
    start_time = System.monotonic_time(:microsecond)

    # Apply transformers
    transformed_data = apply_transformers(data, stage.transformers)

    # Execute systems
    result = if stage.parallel do
      execute_systems_parallel(stage.systems, transformed_data, stage.timeout)
    else
      execute_systems_sequential(stage.systems, transformed_data)
    end

    # Record timing
    end_time = System.monotonic_time(:microsecond)
    record_stage_timing(state, stage.name, end_time - start_time)

    result
  end

  defp execute_systems_sequential([], data), do: {:ok, data}
  defp execute_systems_sequential([system | rest], data) do
    case execute_system_with_data(system, data) do
      {:ok, new_data} ->
        execute_systems_sequential(rest, new_data)

      {:error, _reason} = error ->
        error
    end
  end

  defp execute_systems_parallel(systems, data, timeout) do
    tasks = Enum.map(systems, fn system ->
      Task.async(fn -> execute_system_with_data(system, data) end)
    end)

    results = Task.yield_many(tasks, timeout)

    # Check for failures or timeouts
    failed = Enum.find(results, fn {_task, result} ->
      case result do
        {:ok, {:error, _}} -> true
        nil -> true  # Timeout
        _ -> false
      end
    end)

    if failed do
      {:error, :parallel_execution_failed}
    else
      # Merge results
      merged_data = Enum.reduce(results, data, fn {_task, {:ok, {:ok, result_data}}}, acc ->
        Map.merge(acc, result_data)
      end)

      {:ok, merged_data}
    end
  end

  defp execute_system_with_data(system, data) do
    try do
      # Initialize system if needed
      system_state = case system.init(%{}) do
        {:ok, state} -> state
        _ -> %{}
      end

      # Get entities for this system
      entities = if function_exported?(system, :query_entities, 0) do
        system.query_entities()
      else
        []
      end

      # Execute system
      case system.execute(entities, system_state) do
        {:ok, _new_state} ->
          # For pipeline, we care about data transformation
          {:ok, data}

        error ->
          error
      end
    rescue
      exception ->
        Logger.error("System #{inspect(system)} failed: #{inspect(exception)}")
        {:error, exception}
    end
  end

  defp apply_transformers(data, transformers) do
    Enum.reduce(transformers, data, fn transformer, acc ->
      transformer.(acc)
    end)
  end

  defp find_stage(stages, name) do
    Enum.find(stages, &(&1.name == name))
  end

  defp check_circuit_breaker(circuit_breakers, stage_name) do
    case Map.get(circuit_breakers, stage_name) do
      nil -> :closed
      %{state: state} -> state
    end
  end

  defp reset_stage_circuit_breaker(state, stage_name) do
    if breaker = Map.get(state.circuit_breakers, stage_name) do
      new_breaker = %{breaker | failures: 0, state: :closed}
      new_breakers = Map.put(state.circuit_breakers, stage_name, new_breaker)
      %{state | circuit_breakers: new_breakers}
    else
      state
    end
  end

  defp trip_stage_circuit_breaker(state, stage_name) do
    if breaker = Map.get(state.circuit_breakers, stage_name) do
      new_failures = breaker.failures + 1
      new_state = if new_failures >= breaker.threshold do
        :open
      else
        :closed
      end

      new_breaker = %{breaker | failures: new_failures, state: new_state}
      new_breakers = Map.put(state.circuit_breakers, stage_name, new_breaker)
      %{state | circuit_breakers: new_breakers}
    else
      state
    end
  end

  defp record_stage_timing(state, stage_name, duration) do
    timings = Map.get(state.metrics, :stage_timings, %{})
    stage_timings = Map.get(timings, stage_name, [])

    # Keep last 100 timings
    new_timings = [duration | Enum.take(stage_timings, 99)]

    updated_timings = Map.put(timings, stage_name, new_timings)
    new_metrics = Map.put(state.metrics, :stage_timings, updated_timings)

    %{state | metrics: new_metrics}
  end

  defp update_execution_metrics(metrics, duration, result) do
    executions = Map.get(metrics, :executions, 0) + 1
    failures = case result do
      {:error, _} -> Map.get(metrics, :failures, 0) + 1
      _ -> Map.get(metrics, :failures, 0)
    end

    %{metrics |
      executions: executions,
      failures: failures,
      last_execution_time: duration,
      success_rate: (executions - failures) / executions * 100
    }
  end

  defp default_error_handler(_error) do
    :skip
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
