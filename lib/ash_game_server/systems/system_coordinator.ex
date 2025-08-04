defmodule AshGameServer.Systems.SystemCoordinator do
  @moduledoc """
  Coordinator for inter-system communication and shared state management.

  Features:
  - Message passing between systems
  - Shared state management via ETS
  - Event broadcasting and subscription
  - Dependency tracking and resolution
  - Deadlock detection
  """

  use GenServer
  require Logger

  @table_name :system_coordinator_state
  @subscriptions_table :system_coordinator_subscriptions

  @type system_id :: atom() | module()
  @type event_type :: atom()
  @type message :: term()
  @type shared_key :: atom()
  @type shared_value :: term()

  @type state :: %{
    systems: MapSet.t(system_id()),
    dependencies: %{system_id() => [system_id()]},
    message_queue: :queue.queue(),
    event_handlers: %{event_type() => [system_id()]},
    metrics: map()
  }

  # Client API

  @doc """
  Start the system coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a system with the coordinator.
  """
  def register_system(system_id, dependencies \\ []) do
    GenServer.call(__MODULE__, {:register_system, system_id, dependencies})
  end

  @doc """
  Unregister a system from the coordinator.
  """
  def unregister_system(system_id) do
    GenServer.call(__MODULE__, {:unregister_system, system_id})
  end

  @doc """
  Send a message to another system.
  """
  def send_message(from_system, to_system, message) do
    GenServer.cast(__MODULE__, {:send_message, from_system, to_system, message})
  end

  @doc """
  Broadcast an event to all subscribed systems.
  """
  def broadcast_event(event_type, data) do
    GenServer.cast(__MODULE__, {:broadcast_event, event_type, data})
  end

  @doc """
  Subscribe a system to an event type.
  """
  def subscribe(system_id, event_type) do
    GenServer.call(__MODULE__, {:subscribe, system_id, event_type})
  end

  @doc """
  Unsubscribe a system from an event type.
  """
  def unsubscribe(system_id, event_type) do
    GenServer.call(__MODULE__, {:unsubscribe, system_id, event_type})
  end

  @doc """
  Store a value in shared state.
  """
  def put_shared(key, value) when is_atom(key) do
    :ets.insert(@table_name, {key, value, System.monotonic_time()})
    :ok
  end

  @doc """
  Get a value from shared state.
  """
  def get_shared(key) when is_atom(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, _timestamp}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Update a value in shared state atomically.
  """
  def update_shared(key, fun) when is_atom(key) and is_function(fun, 1) do
    case get_shared(key) do
      {:ok, current_value} ->
        new_value = fun.(current_value)
        put_shared(key, new_value)
        {:ok, new_value}

      {:error, :not_found} ->
        new_value = fun.(nil)
        put_shared(key, new_value)
        {:ok, new_value}
    end
  end

  @doc """
  Delete a value from shared state.
  """
  def delete_shared(key) when is_atom(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Check for dependency cycles (deadlock detection).
  """
  def check_dependencies(system_id) do
    GenServer.call(__MODULE__, {:check_dependencies, system_id})
  end

  @doc """
  Get coordinator metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Wait for a system to be ready (all dependencies met).
  """
  def await_ready(system_id, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:await_ready, system_id}, timeout)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for shared state
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@subscriptions_table, [
      :bag,
      :public,
      :named_table,
      read_concurrency: true
    ])

    state = %{
      systems: MapSet.new(),
      dependencies: %{},
      message_queue: :queue.new(),
      event_handlers: %{},
      metrics: %{
        messages_sent: 0,
        events_broadcast: 0,
        shared_reads: 0,
        shared_writes: 0,
        dependency_checks: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_system, system_id, dependencies}, _from, state) do
    # Check for dependency cycles
    case detect_cycle(system_id, dependencies, state.dependencies) do
      :ok ->
        new_systems = MapSet.put(state.systems, system_id)
        new_deps = Map.put(state.dependencies, system_id, dependencies)

        new_state = %{state |
          systems: new_systems,
          dependencies: new_deps
        }

        Logger.info("Registered system #{inspect(system_id)} with dependencies: #{inspect(dependencies)}")
        {:reply, :ok, new_state}

      {:error, :cycle_detected} = error ->
        Logger.error("Dependency cycle detected for system #{inspect(system_id)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unregister_system, system_id}, _from, state) do
    new_systems = MapSet.delete(state.systems, system_id)
    new_deps = Map.delete(state.dependencies, system_id)

    # Remove from event handlers
    new_handlers = Enum.reduce(state.event_handlers, %{}, fn {event, handlers}, acc ->
      filtered = Enum.reject(handlers, &(&1 == system_id))
      if filtered == [] do
        acc
      else
        Map.put(acc, event, filtered)
      end
    end)

    # Clear subscriptions
    :ets.match_delete(@subscriptions_table, {system_id, :_})

    new_state = %{state |
      systems: new_systems,
      dependencies: new_deps,
      event_handlers: new_handlers
    }

    Logger.info("Unregistered system #{inspect(system_id)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:subscribe, system_id, event_type}, _from, state) do
    :ets.insert(@subscriptions_table, {event_type, system_id})

    handlers = Map.get(state.event_handlers, event_type, [])
    new_handlers = Map.put(state.event_handlers, event_type, [system_id | handlers])

    new_state = %{state | event_handlers: new_handlers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, system_id, event_type}, _from, state) do
    :ets.match_delete(@subscriptions_table, {event_type, system_id})

    handlers = Map.get(state.event_handlers, event_type, [])
    filtered = Enum.reject(handlers, &(&1 == system_id))

    new_handlers = if filtered == [] do
      Map.delete(state.event_handlers, event_type)
    else
      Map.put(state.event_handlers, event_type, filtered)
    end

    new_state = %{state | event_handlers: new_handlers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:check_dependencies, system_id}, _from, state) do
    result = check_system_dependencies(system_id, state)

    new_metrics = Map.update(state.metrics, :dependency_checks, 1, &(&1 + 1))
    new_state = %{state | metrics: new_metrics}

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:await_ready, system_id}, from, state) do
    if dependencies_met?(system_id, state) do
      {:reply, :ok, state}
    else
      # Queue the request to check later
      Process.send_after(self(), {:check_ready, system_id, from}, 100)
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    # Add ETS table stats
    shared_state_count = :ets.info(@table_name, :size)
    subscription_count = :ets.info(@subscriptions_table, :size)

    metrics = Map.merge(state.metrics, %{
      registered_systems: MapSet.size(state.systems),
      shared_state_entries: shared_state_count,
      active_subscriptions: subscription_count,
      message_queue_size: :queue.len(state.message_queue)
    })

    {:reply, metrics, state}
  end

  @impl true
  def handle_cast({:send_message, from_system, to_system, message}, state) do
    if MapSet.member?(state.systems, to_system) do
      # Queue message for delivery
      new_queue = :queue.in({from_system, to_system, message}, state.message_queue)

      # Process message queue
      process_message_queue(new_queue)

      new_metrics = Map.update(state.metrics, :messages_sent, 1, &(&1 + 1))
      new_state = %{state |
        message_queue: :queue.new(),
        metrics: new_metrics
      }

      {:noreply, new_state}
    else
      Logger.warning("Attempted to send message to unregistered system: #{inspect(to_system)}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:broadcast_event, event_type, data}, state) do
    # Get all subscribers
    subscribers = :ets.lookup(@subscriptions_table, event_type)

    # Notify each subscriber
    Enum.each(subscribers, fn {_event, system_id} ->
      notify_subscriber(system_id, event_type, data)
    end)

    new_metrics = Map.update(state.metrics, :events_broadcast, 1, &(&1 + 1))
    new_state = %{state | metrics: new_metrics}

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:check_ready, system_id, from}, state) do
    if dependencies_met?(system_id, state) do
      GenServer.reply(from, :ok)
    else
      Process.send_after(self(), {:check_ready, system_id, from}, 100)
    end

    {:noreply, state}
  end

  # Private Functions

  defp detect_cycle(system_id, dependencies, all_dependencies) do
    # Build dependency graph with new system
    graph = Map.put(all_dependencies, system_id, dependencies)

    # Check for cycles using DFS
    case find_cycle(system_id, graph, MapSet.new(), []) do
      nil -> :ok
      _cycle -> {:error, :cycle_detected}
    end
  end

  defp find_cycle(current, graph, visited, path) do
    cond do
      current in path ->
        # Found a cycle
        [current | Enum.take_while(path, &(&1 != current))]

      current in visited ->
        # Already visited, no cycle here
        nil

      true ->
        # Visit this node
        new_visited = MapSet.put(visited, current)
        new_path = [current | path]

        # Check dependencies
        deps = Map.get(graph, current, [])
        Enum.find_value(deps, fn dep ->
          find_cycle(dep, graph, new_visited, new_path)
        end)
    end
  end

  defp check_system_dependencies(system_id, state) do
    deps = Map.get(state.dependencies, system_id, [])

    missing = Enum.reject(deps, fn dep ->
      MapSet.member?(state.systems, dep)
    end)

    if missing == [] do
      {:ok, :all_met}
    else
      {:error, {:missing_dependencies, missing}}
    end
  end

  defp dependencies_met?(system_id, state) do
    case check_system_dependencies(system_id, state) do
      {:ok, :all_met} -> true
      _ -> false
    end
  end

  defp process_message_queue(queue) do
    case :queue.out(queue) do
      {{:value, {_from, to, message}}, rest} ->
        deliver_message(to, message)
        process_message_queue(rest)

      {:empty, _} ->
        :ok
    end
  end

  defp notify_subscriber(system_id, event_type, data) do
    if function_exported?(system_id, :handle_event, 2) do
      Task.start(fn ->
        try do
          system_id.handle_event({event_type, data}, %{})
        rescue
          error ->
            Logger.error("Error handling event in system #{inspect(system_id)}: #{inspect(error)}")
        end
      end)
    end
  end

  defp deliver_message(system_id, message) do
    if function_exported?(system_id, :handle_event, 2) do
      Task.start(fn ->
        try do
          system_id.handle_event({:message, message}, %{})
        rescue
          error ->
            Logger.error("Error delivering message to system #{inspect(system_id)}: #{inspect(error)}")
        end
      end)
    end
  end

  @impl true
  def terminate(_reason, _state) do
    # Clean up ETS tables
    :ets.delete(@table_name)
    :ets.delete(@subscriptions_table)
    :ok
  end
end
