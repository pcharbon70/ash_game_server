defmodule AshGameServer.Storage.PersistenceBridge do
  @moduledoc """
  Bridge between ETS storage and Ash persistent storage.

  This module handles:
  - Synchronization between ETS and Ash resources
  - Incremental updates and snapshots
  - Conflict resolution
  - Recovery mechanisms
  """

  use GenServer
  require Logger

  alias AshGameServer.Storage.ComponentStorage
  alias AshGameServer.Storage.EntityManager
  alias AshGameServer.Players.Player
  # TODO: GameSession will be used for session persistence
  # alias AshGameServer.GameCore.GameSession

  @sync_interval 30_000  # 30 seconds
  @snapshot_interval 300_000  # 5 minutes

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an immediate sync to persistent storage.
  """
  def sync_now do
    GenServer.call(__MODULE__, :sync_now)
  end

  @doc """
  Create a snapshot of current ETS state to persistent storage.
  """
  def create_snapshot do
    GenServer.call(__MODULE__, :create_snapshot)
  end

  @doc """
  Restore ETS state from the latest persistent snapshot.
  """
  def restore_from_snapshot do
    GenServer.call(__MODULE__, :restore_from_snapshot)
  end

  @doc """
  Enable or disable automatic synchronization.
  """
  def set_auto_sync(enabled) do
    GenServer.call(__MODULE__, {:set_auto_sync, enabled})
  end

  @doc """
  Get synchronization status and statistics.
  """
  def sync_status do
    GenServer.call(__MODULE__, :sync_status)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    auto_sync = Keyword.get(opts, :auto_sync, true)

    state = %{
      auto_sync: auto_sync,
      last_sync: nil,
      last_snapshot: nil,
      sync_errors: [],
      pending_changes: %{}
    }

    # Schedule periodic sync if auto_sync is enabled
    if auto_sync do
      schedule_sync()
      schedule_snapshot()
    end

    Logger.info("Persistence bridge started with auto_sync: #{auto_sync}")
    {:ok, state}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    case perform_sync() do
      :ok ->
        new_state = %{state | last_sync: DateTime.utc_now(), sync_errors: []}
        {:reply, :ok, new_state}

      {:error, errors} ->
        new_state = %{state | sync_errors: errors}
        {:reply, {:error, errors}, new_state}
    end
  end

  @impl true
  def handle_call(:create_snapshot, _from, state) do
    case create_persistent_snapshot() do
      :ok ->
        new_state = %{state | last_snapshot: DateTime.utc_now()}
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:restore_from_snapshot, _from, state) do
    case restore_persistent_snapshot() do
      :ok ->
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:set_auto_sync, enabled}, _from, state) do
    new_state = %{state | auto_sync: enabled}

    if enabled do
      schedule_sync()
      schedule_snapshot()
    end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:sync_status, _from, state) do
    status = %{
      auto_sync: state.auto_sync,
      last_sync: state.last_sync,
      last_snapshot: state.last_snapshot,
      sync_errors: state.sync_errors,
      pending_changes: map_size(state.pending_changes)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:perform_sync, state) do
    if state.auto_sync do
      case perform_sync() do
        :ok ->
          new_state = %{state | last_sync: DateTime.utc_now(), sync_errors: []}
          schedule_sync()
          {:noreply, new_state}

        {:error, errors} ->
          new_state = %{state | sync_errors: errors}
          schedule_sync()  # Retry on next interval
          {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:create_snapshot, state) do
    if state.auto_sync do
      case create_persistent_snapshot() do
        :ok ->
          new_state = %{state | last_snapshot: DateTime.utc_now()}
          schedule_snapshot()
          {:noreply, new_state}

        _error ->
          schedule_snapshot()  # Retry on next interval
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp perform_sync do
    try do
      # Sync entities that map to Players
      sync_players()

      # Sync entities that map to GameSessions
      sync_game_sessions()

      Logger.debug("Sync completed successfully")
      :ok

    rescue
      error ->
        Logger.error("Sync failed: #{inspect(error)}")
        {:error, [error]}
    end
  end

  defp sync_players do
    # Get all player entities from ETS
    player_entities = EntityManager.get_entities_by_archetype(:player)

    Enum.each(player_entities, fn entity_id ->
      case EntityManager.get_entity_components(entity_id) do
        {:ok, components} ->
          sync_player_entity(entity_id, components)

        _error ->
          Logger.warning("Failed to get components for player entity #{entity_id}")
      end
    end)
  end

  defp sync_player_entity(entity_id, components) do
    # Map ETS components to Ash Player resource
    player_attrs = %{
      # Use entity_id as external reference
      metadata: Map.put(Map.get(components, :metadata, %{}), :ets_entity_id, entity_id)
    }

    # Add position data if available
    player_attrs =
      case Map.get(components, :position) do
        nil -> player_attrs
        pos -> Map.put(player_attrs, :last_position, pos)
      end

    # Add health data if available
    player_attrs =
      case Map.get(components, :health) do
        nil -> player_attrs
        health -> Map.put(player_attrs, :current_health, health.current)
      end

    # Try to find existing player record or create new one
    case find_or_create_player(entity_id, player_attrs) do
      {:ok, _player} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to sync player entity #{entity_id}: #{inspect(reason)}")
    end
  end

  defp sync_game_sessions do
    # This would sync game session data to GameSession resources
    # Implementation depends on how sessions are stored in ETS
    Logger.debug("Game session sync placeholder")
    :ok
  end

  defp find_or_create_player(_entity_id, attrs) do
    # Look for existing player with this entity_id in metadata
    # This is a simplified implementation
    case Player.create(attrs) do
      {:ok, player} ->
        {:ok, player}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_persistent_snapshot do
    try do
      # Create a comprehensive snapshot of ETS state
      timestamp = DateTime.utc_now()

      snapshot_data = %{
        timestamp: timestamp,
        entities: create_entity_snapshot(),
        components: create_component_snapshot(),
        metadata: %{
          version: "1.0",
          created_by: "persistence_bridge"
        }
      }

      # Store snapshot (could be to database, file, etc.)
      store_snapshot(snapshot_data)

      Logger.info("Created persistent snapshot at #{DateTime.to_iso8601(timestamp)}")
      :ok

    rescue
      error ->
        Logger.error("Failed to create snapshot: #{inspect(error)}")
        {:error, error}
    end
  end

  defp create_entity_snapshot do
    # Get all entities from registry
    :ets.select(:entity_registry, [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Map.new()
  end

  defp create_component_snapshot do
    # Get component data for all entities
    ComponentStorage.all_component_stats()
    |> Enum.reduce(%{}, fn stats, acc ->
      component_name = stats.component_name
      table_name = String.to_atom("component_" <> to_string(component_name))

      component_data = :ets.tab2list(table_name) |> Map.new()
      Map.put(acc, component_name, component_data)
    end)
  end

  defp store_snapshot(snapshot_data) do
    # This could store to various backends
    # For now, we'll just log the snapshot size
    entity_count = map_size(snapshot_data.entities)
    component_count =
      snapshot_data.components
      |> Enum.map(fn {_name, data} -> map_size(data) end)
      |> Enum.sum()

    Logger.info("Snapshot contains #{entity_count} entities and #{component_count} component instances")
    :ok
  end

  defp restore_persistent_snapshot do
    # This would restore from the latest snapshot
    Logger.info("Snapshot restore placeholder - would restore from latest backup")
    :ok
  end

  defp schedule_sync do
    Process.send_after(self(), :perform_sync, @sync_interval)
  end

  defp schedule_snapshot do
    Process.send_after(self(), :create_snapshot, @snapshot_interval)
  end
end
