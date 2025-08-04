defmodule AshGameServer.Storage.TableManager do
  @moduledoc """
  GenServer for managing ETS tables and their lifecycle.

  This module handles:
  - Table creation and destruction
  - Table monitoring and recovery
  - Access control and ownership
  - Backup and restore operations
  """
  use GenServer
  require Logger

  @backup_dir "storage/backups"

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Create a new ETS table with the given configuration.
  """
  def create_table(manager, table_name, type \\ :set, options \\ [:public, :named_table]) do
    GenServer.call(manager, {:create_table, table_name, type, options})
  end

  @doc """
  Delete an ETS table.
  """
  def delete_table(manager, table_name) do
    GenServer.call(manager, {:delete_table, table_name})
  end

  @doc """
  List all tables managed by this process.
  """
  def list_tables(manager \\ __MODULE__) do
    GenServer.call(manager, :list_tables)
  end

  @doc """
  Get information about a specific table.
  """
  def table_info(manager, table_name) do
    GenServer.call(manager, {:table_info, table_name})
  end

  @doc """
  Backup all managed tables to disk.
  """
  def backup_tables(manager \\ __MODULE__, backup_path \\ nil) do
    GenServer.call(manager, {:backup_tables, backup_path})
  end

  @doc """
  Restore tables from a backup file.
  """
  def restore_tables(manager \\ __MODULE__, backup_path) do
    GenServer.call(manager, {:restore_tables, backup_path})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, :default_manager)

    # Ensure backup directory exists
    File.mkdir_p!(@backup_dir)

    state = %{
      name: name,
      tables: %{},
      monitors: %{}
    }

    Logger.info("TableManager #{name} started")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_table, table_name, type, options}, _from, state) do
    case create_ets_table(table_name, type, options) do
      {:ok, table_ref} ->
        # Monitor the table for cleanup
        monitor_ref = :ets.setopts(table_ref, {:heir, self(), table_name})

        new_state = %{
          state |
          tables: Map.put(state.tables, table_name, %{
            ref: table_ref,
            type: type,
            options: options,
            created_at: DateTime.utc_now(),
            access_count: 0
          }),
          monitors: Map.put(state.monitors, table_name, monitor_ref)
        }

        Logger.debug("Created ETS table: #{table_name}")
        {:reply, {:ok, table_ref}, new_state}

      {:error, reason} ->
        Logger.error("Failed to create ETS table #{table_name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete_table, table_name}, _from, state) do
    case Map.get(state.tables, table_name) do
      nil ->
        {:reply, {:error, :table_not_found}, state}

      table_info ->
        :ets.delete(table_info.ref)

        new_state = %{
          state |
          tables: Map.delete(state.tables, table_name),
          monitors: Map.delete(state.monitors, table_name)
        }

        Logger.debug("Deleted ETS table: #{table_name}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_tables, _from, state) do
    table_list =
      state.tables
      |> Enum.map(fn {name, info} ->
        %{
          name: name,
          type: info.type,
          size: :ets.info(info.ref, :size),
          memory: :ets.info(info.ref, :memory),
          created_at: info.created_at,
          access_count: info.access_count
        }
      end)

    {:reply, table_list, state}
  end

  @impl true
  def handle_call({:table_info, table_name}, _from, state) do
    case Map.get(state.tables, table_name) do
      nil ->
        {:reply, {:error, :table_not_found}, state}

      table_info ->
        info = %{
          name: table_name,
          type: table_info.type,
          size: :ets.info(table_info.ref, :size),
          memory: :ets.info(table_info.ref, :memory),
          owner: :ets.info(table_info.ref, :owner),
          created_at: table_info.created_at,
          access_count: table_info.access_count
        }

        {:reply, {:ok, info}, state}
    end
  end

  @impl true
  def handle_call({:backup_tables, backup_path}, _from, state) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    backup_file = backup_path || Path.join(@backup_dir, "tables_#{timestamp}.backup")

    try do
      backup_data = %{
        timestamp: timestamp,
        manager: state.name,
        tables: create_backup_data(state.tables)
      }

      File.write!(backup_file, :erlang.term_to_binary(backup_data))
      Logger.info("Created backup: #{backup_file}")
      {:reply, {:ok, backup_file}, state}

    rescue
      error ->
        Logger.error("Backup failed: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:restore_tables, backup_path}, _from, state) do
    try do
      backup_data =
        backup_path
        |> File.read!()
        |> :erlang.binary_to_term()

      # Restore tables from backup
      restored_tables = restore_backup_data(backup_data.tables)

      new_state = %{
        state |
        tables: Map.merge(state.tables, restored_tables)
      }

      Logger.info("Restored tables from: #{backup_path}")
      {:reply, {:ok, map_size(restored_tables)}, new_state}

    rescue
      error ->
        Logger.error("Restore failed: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_info({:ETS_TRANSFER, _table_ref, _from_pid, table_name}, state) do
    Logger.warning("ETS table #{table_name} transferred, updating ownership")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp create_ets_table(table_name, type, options) do
    try do
      table_ref = :ets.new(table_name, [type | options])
      {:ok, table_ref}
    rescue
      error ->
        {:error, error}
    end
  end

  defp create_backup_data(tables) do
    tables
    |> Enum.map(fn {name, info} ->
      table_data = :ets.tab2list(info.ref)

      %{
        name: name,
        type: info.type,
        options: info.options,
        data: table_data,
        metadata: %{
          created_at: info.created_at,
          access_count: info.access_count
        }
      }
    end)
  end

  defp restore_backup_data(backup_tables) do
    backup_tables
    |> Enum.reduce(%{}, fn table_backup, acc ->
      restore_single_table(table_backup, acc)
    end)
  end

  defp restore_single_table(table_backup, acc) do
    case create_ets_table(table_backup.name, table_backup.type, table_backup.options) do
      {:ok, table_ref} ->
        restore_table_contents(table_ref, table_backup)
        table_info = build_table_info(table_ref, table_backup)
        Map.put(acc, table_backup.name, table_info)

      {:error, reason} ->
        Logger.error("Failed to restore table #{table_backup.name}: #{inspect(reason)}")
        acc
    end
  end

  defp restore_table_contents(table_ref, table_backup) do
    Enum.each(table_backup.data, fn record ->
      :ets.insert(table_ref, record)
    end)
  end

  defp build_table_info(table_ref, table_backup) do
    %{
      ref: table_ref,
      type: table_backup.type,
      options: table_backup.options,
      created_at: table_backup.metadata.created_at,
      access_count: table_backup.metadata.access_count
    }
  end
end
