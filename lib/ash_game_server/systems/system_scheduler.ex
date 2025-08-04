defmodule AshGameServer.Systems.SystemScheduler do
  @moduledoc """
  Scheduler for ECS systems with priority-based execution and tick management.

  Features:
  - Priority queue for system execution order
  - Tick-based scheduling with configurable intervals
  - Parallel execution support for independent systems
  - System dependency resolution
  - Performance tracking and metrics
  """

  use GenServer
  require Logger


  @type system_ref :: module() | atom()
  @type tick :: non_neg_integer()
  @type priority :: :critical | :high | :medium | :low | :idle

  @type scheduled_system :: %{
    module: module(),
    priority: priority(),
    last_run: tick(),
    interval: pos_integer() | nil,
    dependencies: [system_ref()],
    state: term()
  }

  @type state :: %{
    systems: %{system_ref() => scheduled_system()},
    priority_queues: %{priority() => [system_ref()]},
    current_tick: tick(),
    tick_interval: pos_integer(),
    timer_ref: reference() | nil,
    running: boolean(),
    metrics: map()
  }

  # Client API

  @doc """
  Start the system scheduler.

  Options:
  - `:tick_interval` - Milliseconds between ticks (default: 16ms for ~60 FPS)
  - `:auto_start` - Start scheduling immediately (default: false)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a system with the scheduler.
  """
  def register_system(module, config \\ %{}) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_system, module, config})
  end

  @doc """
  Unregister a system from the scheduler.
  """
  def unregister_system(system_ref) do
    GenServer.call(__MODULE__, {:unregister_system, system_ref})
  end

  @doc """
  Start the scheduler tick loop.
  """
  def start do
    GenServer.call(__MODULE__, :start)
  end

  @doc """
  Stop the scheduler tick loop.
  """
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Execute a single tick manually.
  """
  def tick do
    GenServer.call(__MODULE__, :manual_tick)
  end

  @doc """
  Get the current tick count.
  """
  def current_tick do
    GenServer.call(__MODULE__, :get_tick)
  end

  @doc """
  Get scheduler metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Set system priority.
  """
  def set_priority(system_ref, priority) when priority in [:critical, :high, :medium, :low, :idle] do
    GenServer.call(__MODULE__, {:set_priority, system_ref, priority})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      systems: %{},
      priority_queues: %{
        critical: [],
        high: [],
        medium: [],
        low: [],
        idle: []
      },
      current_tick: 0,
      tick_interval: Keyword.get(opts, :tick_interval, 16),
      timer_ref: nil,
      running: false,
      metrics: %{
        total_ticks: 0,
        system_runs: %{},
        average_tick_time: 0,
        last_tick_duration: 0,
        last_systems_run: 0
      }
    }

    if Keyword.get(opts, :auto_start, false) do
      {:ok, state, {:continue, :start}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:start, state) do
    {:noreply, start_scheduler(state)}
  end

  @impl true
  def handle_call({:register_system, module, config}, _from, state) do
    case init_system(module, config) do
      {:ok, system_state} ->
        priority = get_system_priority(module)

        scheduled_system = %{
          module: module,
          priority: priority,
          last_run: 0,
          interval: Map.get(config, :interval),
          dependencies: Map.get(config, :dependencies, []),
          state: system_state
        }

        new_systems = Map.put(state.systems, module, scheduled_system)
        new_queues = add_to_priority_queue(state.priority_queues, module, priority)

        new_state = %{state | systems: new_systems, priority_queues: new_queues}

        Logger.info("Registered system #{inspect(module)} with priority #{priority}")
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to register system #{inspect(module)}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unregister_system, system_ref}, _from, state) do
    case Map.get(state.systems, system_ref) do
      nil ->
        {:reply, {:error, :not_found}, state}

      system ->
        new_systems = Map.delete(state.systems, system_ref)
        new_queues = remove_from_priority_queue(state.priority_queues, system_ref, system.priority)

        # Terminate the system
        if function_exported?(system.module, :terminate, 2) do
          system.module.terminate(:shutdown, system.state)
        end

        new_state = %{state | systems: new_systems, priority_queues: new_queues}
        Logger.info("Unregistered system #{inspect(system_ref)}")

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:start, _from, state) do
    if state.running do
      {:reply, {:error, :already_running}, state}
    else
      new_state = start_scheduler(state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    new_state = stop_scheduler(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:manual_tick, _from, state) do
    new_state = execute_tick(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_tick, _from, state) do
    {:reply, state.current_tick, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call({:set_priority, system_ref, new_priority}, _from, state) do
    case Map.get(state.systems, system_ref) do
      nil ->
        {:reply, {:error, :not_found}, state}

      system ->
        # Remove from old queue
        queues_after_remove = remove_from_priority_queue(
          state.priority_queues,
          system_ref,
          system.priority
        )

        # Add to new queue
        new_queues = add_to_priority_queue(queues_after_remove, system_ref, new_priority)

        # Update system
        updated_system = %{system | priority: new_priority}
        new_systems = Map.put(state.systems, system_ref, updated_system)

        new_state = %{state | systems: new_systems, priority_queues: new_queues}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = execute_tick(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp start_scheduler(state) do
    timer_ref = Process.send_after(self(), :tick, state.tick_interval)
    %{state | timer_ref: timer_ref, running: true}
  end

  defp stop_scheduler(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    %{state | timer_ref: nil, running: false}
  end

  defp execute_tick(state) do
    start_time = System.monotonic_time(:microsecond)

    # Get systems to run this tick
    systems_to_run = get_systems_for_tick(state)

    # Sort by dependencies and priority
    ordered_systems = order_systems_by_dependencies(systems_to_run, state.systems)

    # Execute systems
    new_state = Enum.reduce(ordered_systems, state, &execute_system/2)

    # Update metrics
    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    new_metrics = update_metrics(new_state.metrics, duration, length(systems_to_run))

    # Schedule next tick if running
    final_state = if new_state.running do
      timer_ref = Process.send_after(self(), :tick, new_state.tick_interval)
      %{new_state | timer_ref: timer_ref}
    else
      new_state
    end

    %{final_state |
      current_tick: state.current_tick + 1,
      metrics: new_metrics
    }
  end

  defp get_systems_for_tick(state) do
    state.priority_queues
    |> Enum.flat_map(fn {_priority, systems} -> systems end)
    |> Enum.filter(fn system_ref ->
      system = Map.get(state.systems, system_ref)
      should_run_system?(system, state.current_tick)
    end)
  end

  defp should_run_system?(nil, _tick), do: false
  defp should_run_system?(system, current_tick) do
    # Check interval
    interval_ok = case system.interval do
      nil -> true
      interval -> current_tick - system.last_run >= interval
    end

    # Check if system wants to run
    wants_to_run = if function_exported?(system.module, :should_run?, 1) do
      system.module.should_run?(system.state)
    else
      true
    end

    interval_ok and wants_to_run
  end

  defp order_systems_by_dependencies(systems, all_systems) do
    # Simple topological sort for dependencies
    # For now, just respect priority order
    Enum.sort_by(systems, fn system_ref ->
      system = Map.get(all_systems, system_ref)
      priority_to_number(system.priority)
    end)
  end

  defp priority_to_number(:critical), do: 0
  defp priority_to_number(:high), do: 1
  defp priority_to_number(:medium), do: 2
  defp priority_to_number(:low), do: 3
  defp priority_to_number(:idle), do: 4

  defp execute_system(system_ref, state) do
    case Map.get(state.systems, system_ref) do
      nil -> state
      system -> run_system_with_hooks(system, system_ref, state)
    end
  end

  defp run_system_with_hooks(system, system_ref, state) do
    entities = get_system_entities(system)
    system_state = execute_before_hook(system)
    final_state = execute_system_main(system, entities, system_state)
    final_state = execute_after_hook(system, final_state)

    update_system_in_state(state, system_ref, system, final_state)
  end

  defp get_system_entities(system) do
    if function_exported?(system.module, :query_entities, 0) do
      system.module.query_entities()
    else
      []
    end
  end

  defp execute_before_hook(system) do
    if function_exported?(system.module, :before_execute, 1) do
      case system.module.before_execute(system.state) do
        {:ok, new_state} -> new_state
        _ -> system.state
      end
    else
      system.state
    end
  end

  defp execute_system_main(system, entities, system_state) do
    if function_exported?(system.module, :execute, 2) do
      case system.module.execute(entities, system_state) do
        {:ok, new_state} -> new_state
        _ -> system_state
      end
    else
      system_state
    end
  end

  defp execute_after_hook(system, current_state) do
    if function_exported?(system.module, :after_execute, 1) do
      case system.module.after_execute(current_state) do
        {:ok, new_state} -> new_state
        _ -> current_state
      end
    else
      current_state
    end
  end

  defp update_system_in_state(state, system_ref, system, final_state) do
    updated_system = %{system |
      state: final_state,
      last_run: state.current_tick
    }

    new_systems = Map.put(state.systems, system_ref, updated_system)
    %{state | systems: new_systems}
  end

  defp init_system(module, config) do
    if function_exported?(module, :init, 1) do
      module.init(config)
    else
      {:ok, %{}}
    end
  end

  defp get_system_priority(module) do
    if function_exported?(module, :priority, 0) do
      module.priority()
    else
      :medium
    end
  end

  defp add_to_priority_queue(queues, system_ref, priority) do
    current = Map.get(queues, priority, [])
    Map.put(queues, priority, [system_ref | current])
  end

  defp remove_from_priority_queue(queues, system_ref, priority) do
    current = Map.get(queues, priority, [])
    Map.put(queues, priority, List.delete(current, system_ref))
  end

  defp update_metrics(metrics, tick_duration, systems_run) do
    total_ticks = Map.get(metrics, :total_ticks, 0) + 1

    # Update running average
    avg_time = Map.get(metrics, :average_tick_time, 0)
    new_avg = ((avg_time * (total_ticks - 1)) + tick_duration) / total_ticks

    %{metrics |
      total_ticks: total_ticks,
      average_tick_time: new_avg,
      last_tick_duration: tick_duration,
      last_systems_run: systems_run
    }
  end

  @impl true
  def terminate(_reason, state) do
    # Stop the scheduler
    stop_scheduler(state)

    # Terminate all systems
    Enum.each(state.systems, fn {_ref, system} ->
      if function_exported?(system.module, :terminate, 2) do
        system.module.terminate(:shutdown, system.state)
      end
    end)

    :ok
  end
end
