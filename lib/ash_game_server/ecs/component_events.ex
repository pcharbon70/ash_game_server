defmodule AshGameServer.ECS.ComponentEvents do
  @moduledoc """
  Component event system for tracking changes, batching, filtering, and history.

  Provides comprehensive event management for components:
  - Component change event generation
  - Event batching for performance
  - Event filtering and routing
  - Event history and persistence
  - Event replay capabilities for debugging
  - Real-time event streaming
  """
  use GenServer

  # alias AshGameServer.ECS.ComponentRegistry  # TODO: Will be used for metadata lookup

  @type entity_id :: term()
  @type component_name :: atom()
  @type component_data :: map()
  @type event_type :: :created | :updated | :deleted
  @type event_id :: String.t()
  @type timestamp :: integer()

  @type component_event :: %{
    id: event_id(),
    type: event_type(),
    entity_id: entity_id(),
    component: component_name(),
    data: component_data(),
    old_data: component_data() | nil,
    timestamp: timestamp(),
    metadata: map()
  }

  @events_table :component_events
  @event_history_table :component_event_history
  @subscribers_table :component_event_subscribers

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a component creation event.
  """
  @spec component_created(entity_id(), component_name(), component_data(), map()) :: :ok
  def component_created(entity_id, component_name, data, metadata \\ %{}) do
    event = create_event(:created, entity_id, component_name, data, nil, metadata)
    GenServer.cast(__MODULE__, {:record_event, event})
  end

  @doc """
  Records a component update event.
  """
  @spec component_updated(entity_id(), component_name(), component_data(), component_data(), map()) :: :ok
  def component_updated(entity_id, component_name, new_data, old_data, metadata \\ %{}) do
    event = create_event(:updated, entity_id, component_name, new_data, old_data, metadata)
    GenServer.cast(__MODULE__, {:record_event, event})
  end

  @doc """
  Records a component deletion event.
  """
  @spec component_deleted(entity_id(), component_name(), component_data(), map()) :: :ok
  def component_deleted(entity_id, component_name, data, metadata \\ %{}) do
    event = create_event(:deleted, entity_id, component_name, data, nil, metadata)
    GenServer.cast(__MODULE__, {:record_event, event})
  end

  @doc """
  Subscribes to component events with optional filtering.
  """
  @spec subscribe(pid(), keyword()) :: :ok
  def subscribe(pid, filters \\ []) do
    GenServer.call(__MODULE__, {:subscribe, pid, filters})
  end

  @doc """
  Unsubscribes from component events.
  """
  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(pid) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end

  @doc """
  Gets recent events with optional filtering.
  """
  @spec get_recent_events(keyword()) :: [component_event()]
  def get_recent_events(filters \\ []) do
    GenServer.call(__MODULE__, {:get_recent_events, filters})
  end

  @doc """
  Gets event history for a specific entity/component.
  """
  @spec get_event_history(entity_id(), component_name() | nil, keyword()) :: [component_event()]
  def get_event_history(entity_id, component_name \\ nil, opts \\ []) do
    GenServer.call(__MODULE__, {:get_event_history, entity_id, component_name, opts})
  end

  @doc """
  Replays events to recreate component state.
  """
  @spec replay_events(entity_id(), component_name(), timestamp()) :: {:ok, component_data()} | {:error, term()}
  def replay_events(entity_id, component_name, up_to_timestamp) do
    GenServer.call(__MODULE__, {:replay_events, entity_id, component_name, up_to_timestamp})
  end

  @doc """
  Creates a stream of events for real-time processing.
  """
  @spec event_stream(keyword()) :: GenServer.from()
  def event_stream(filters \\ []) do
    GenServer.call(__MODULE__, {:create_stream, filters})
  end

  @doc """
  Gets event statistics and metrics.
  """
  @spec get_event_stats() :: map()
  def get_event_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Flushes pending batched events immediately.
  """
  @spec flush_events() :: :ok
  def flush_events do
    GenServer.cast(__MODULE__, :flush_events)
  end

  @doc """
  Compacts old events to save storage space.
  """
  @spec compact_history(timestamp()) :: :ok
  def compact_history(before_timestamp) do
    GenServer.cast(__MODULE__, {:compact_history, before_timestamp})
  end

  # Private Functions

  defp create_event(type, entity_id, component_name, data, old_data, metadata) do
    %{
      id: generate_event_id(),
      type: type,
      entity_id: entity_id,
      component: component_name,
      data: data,
      old_data: old_data,
      timestamp: System.system_time(:millisecond),
      metadata: metadata
    }
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp should_notify?(event, filters) do
    Enum.all?(filters, fn
      {:entity_id, entity_id} -> event.entity_id == entity_id
      {:component, component} -> event.component == component
      {:type, type} -> event.type == type
      {:since, timestamp} -> event.timestamp >= timestamp
      _ -> true
    end)
  end

  defp broadcast_event(event, subscribers) do
    Enum.each(subscribers, fn {pid, filters} ->
      if should_notify?(event, filters) do
        send(pid, {:component_event, event})
      end
    end)
  end

  defp persist_to_history(event) do
    # Store in persistent history (could be database or file)
    :ets.insert(@event_history_table, {
      {event.entity_id, event.component, event.timestamp},
      event
    })
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@events_table, [:named_table, :public, :ordered_set])
    :ets.new(@event_history_table, [:named_table, :public, :ordered_set])
    :ets.new(@subscribers_table, [:named_table, :public, :bag])

    # Configure batching
    batch_size = Keyword.get(opts, :batch_size, 100)
    batch_timeout = Keyword.get(opts, :batch_timeout, 1000)

    # Schedule periodic flush
    :timer.send_interval(batch_timeout, :flush_batch)

    state = %{
      event_batch: [],
      batch_size: batch_size,
      batch_timeout: batch_timeout,
      stats: %{
        events_processed: 0,
        events_batched: 0,
        subscribers_count: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_event, event}, state) do
    # Add to batch
    new_batch = [event | state.event_batch]

    # Update stats
    new_stats = Map.update!(state.stats, :events_processed, &(&1 + 1))

    # Check if batch is full
    if length(new_batch) >= state.batch_size do
      process_event_batch(new_batch)
      {:noreply, %{state | event_batch: [], stats: new_stats}}
    else
      {:noreply, %{state | event_batch: new_batch, stats: new_stats}}
    end
  end

  @impl true
  def handle_cast(:flush_events, state) do
    if state.event_batch != [] do
      process_event_batch(state.event_batch)
      {:noreply, %{state | event_batch: []}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:compact_history, before_timestamp}, state) do
    # Remove old events from history
    match_spec = [
      {{{:"$1", :"$2", :"$3"}, :"$4"},
       [{:<, :"$3", before_timestamp}],
       [true]}
    ]

    deleted_count = :ets.select_delete(@event_history_table, match_spec)

    # Log compaction
    require Logger
    Logger.info("Compacted #{deleted_count} old events from history")

    {:noreply, state}
  end

  @impl true
  def handle_call({:subscribe, pid, filters}, _from, state) do
    # Monitor subscriber process
    Process.monitor(pid)

    # Add to subscribers
    :ets.insert(@subscribers_table, {pid, filters})

    # Update stats
    new_stats = Map.update!(state.stats, :subscribers_count, &(&1 + 1))

    {:reply, :ok, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    :ets.delete(@subscribers_table, pid)

    # Update stats
    new_stats = Map.update!(state.stats, :subscribers_count, &(&1 - 1))

    {:reply, :ok, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:get_recent_events, filters}, _from, state) do
    # Get recent events from memory table
    events = :ets.tab2list(@events_table)
    |> Enum.map(fn {_timestamp, event} -> event end)
    |> Enum.filter(fn event -> should_notify?(event, filters) end)
    |> Enum.reverse()  # Most recent first

    {:reply, events, state}
  end

  @impl true
  def handle_call({:get_event_history, entity_id, component_name, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since, 0)

    # Build match pattern
    pattern = case component_name do
      nil -> {{entity_id, :_, :"$1"}, :"$2"}
      comp -> {{entity_id, comp, :"$1"}, :"$2"}
    end

    # Build match spec with timestamp filter
    match_spec = [{pattern, [{:>=, :"$1", since}], [:"$2"]}]

    events = :ets.select(@event_history_table, match_spec)
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(limit)

    {:reply, events, state}
  end

  @impl true
  def handle_call({:replay_events, entity_id, component_name, up_to_timestamp}, _from, state) do
    # Get all events for the component up to the timestamp
    pattern = {{entity_id, component_name, :"$1"}, :"$2"}
    match_spec = [{pattern, [{:"=<", :"$1", up_to_timestamp}], [:"$2"]}]

    events = :ets.select(@event_history_table, match_spec)
    |> Enum.sort_by(& &1.timestamp)

    # Replay events to reconstruct state
    final_state = Enum.reduce(events, nil, fn event, _current_state ->
      case event.type do
        :created -> event.data
        :updated -> event.data
        :deleted -> nil
      end
    end)

    result = case final_state do
      nil -> {:error, :no_data}
      data -> {:ok, data}
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_stream, filters}, from, state) do
    # Create a stream consumer
    # This is a simplified implementation
    spawn_link(fn ->
      stream_events(from, filters)
    end)

    {:reply, {:ok, :stream_started}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats = Map.merge(state.stats, %{
      current_batch_size: length(state.event_batch),
      memory_events: :ets.info(@events_table, :size),
      history_events: :ets.info(@event_history_table, :size)
    })

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_info(:flush_batch, state) do
    if state.event_batch != [] do
      process_event_batch(state.event_batch)
      {:noreply, %{state | event_batch: []}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up dead subscriber
    :ets.delete(@subscribers_table, pid)

    # Update stats
    new_stats = Map.update!(state.stats, :subscribers_count, &(&1 - 1))

    {:noreply, %{state | stats: new_stats}}
  end

  defp process_event_batch(events) do
    # Process events in reverse order (oldest first)
    sorted_events = Enum.reverse(events)

    # Store in memory table for recent access
    Enum.each(sorted_events, fn event ->
      :ets.insert(@events_table, {event.timestamp, event})
      persist_to_history(event)
    end)

    # Get current subscribers
    subscribers = :ets.tab2list(@subscribers_table)

    # Broadcast events
    Enum.each(sorted_events, fn event ->
      broadcast_event(event, subscribers)
    end)

    # Clean up old events from memory table (keep last 1000)
    cleanup_memory_events()
  end

  defp cleanup_memory_events do
    events_count = :ets.info(@events_table, :size)

    if events_count > 1000 do
      # Delete oldest events
      to_delete = events_count - 1000

      oldest_keys = :ets.tab2list(@events_table)
      |> Enum.sort_by(fn {timestamp, _} -> timestamp end)
      |> Enum.take(to_delete)
      |> Enum.map(fn {timestamp, _} -> timestamp end)

      Enum.each(oldest_keys, fn key ->
        :ets.delete(@events_table, key)
      end)
    end
  end

  defp stream_events(from, _filters) do
    # This would implement real-time event streaming
    # For now, just acknowledge the stream creation
    GenServer.reply(from, {:ok, :stream_ready})
  end
end
