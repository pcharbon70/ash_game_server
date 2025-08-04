defmodule AshGameServer.Storage.TableSupervisor do
  @moduledoc """
  Supervisor for ETS table management in the game server.

  This supervisor manages the lifecycle of ETS tables used for component storage,
  ensuring tables are created, monitored, and cleaned up properly.
  """
  use Supervisor

  alias AshGameServer.Storage.TableManager

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Main table manager for component storage
      Supervisor.child_spec({TableManager, [name: :component_tables]}, id: :component_tables_manager),

      # Entity registry manager
      Supervisor.child_spec({TableManager, [name: :entity_registry]}, id: :entity_registry_manager),

      # System query cache manager
      Supervisor.child_spec({TableManager, [name: :system_queries]}, id: :system_queries_manager),

      # Statistics and monitoring
      Supervisor.child_spec({TableManager, [name: :table_stats]}, id: :table_stats_manager)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Create a new component table for the given component type.
  """
  def create_component_table(component_name) do
    TableManager.create_table(:component_tables, component_name, :set, [:public, :named_table])
  end

  @doc """
  Get information about all managed tables.
  """
  def table_info do
    TableManager.list_tables()
  end

  @doc """
  Create a backup of all tables to disk.
  """
  def create_backup(backup_path) do
    TableManager.backup_tables(backup_path)
  end

  @doc """
  Restore tables from a backup file.
  """
  def restore_backup(backup_path) do
    TableManager.restore_tables(backup_path)
  end
end
