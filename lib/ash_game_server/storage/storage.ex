defmodule AshGameServer.Storage do
  @moduledoc """
  Main interface for the ETS storage system.
  
  This module provides a unified API for all storage operations
  and manages the integration between different storage components.
  """
  
  alias AshGameServer.Storage.{
    TableSupervisor,
    ComponentStorage,
    EntityManager,
    PersistenceBridge,
    PerformanceMonitor
  }
  
  @doc """
  Initialize the complete storage system.
  """
  def initialize(component_definitions \\ []) do
    # Initialize component storage with definitions
    ComponentStorage.initialize_components(component_definitions)
    
    # Initialize entity management
    EntityManager.initialize()
    
    :ok
  end
  
  @doc """
  Create a new entity with optional archetype and components.
  """
  defdelegate create_entity(opts \\ []), to: EntityManager
  
  @doc """
  Destroy an entity and clean up all its components.
  """
  defdelegate destroy_entity(entity_id), to: EntityManager
  
  @doc """
  Add a component to an entity.
  """
  defdelegate add_component(entity_id, component_name, component_data), to: EntityManager
  
  @doc """
  Remove a component from an entity.
  """
  defdelegate remove_component(entity_id, component_name), to: EntityManager
  
  @doc """
  Get a component for an entity.
  """
  defdelegate get_component(entity_id, component_name), to: ComponentStorage
  
  @doc """
  Get multiple components for an entity.
  """
  defdelegate get_components(entity_id, component_names), to: ComponentStorage
  
  @doc """
  Check if an entity has a specific component.
  """
  defdelegate has_component?(entity_id, component_name), to: ComponentStorage
  
  @doc """
  Query entities that have all specified components.
  """
  defdelegate query_entities(required_components, optional_components \\ []), to: EntityManager
  
  @doc """
  Get all entities with a specific archetype.
  """
  defdelegate get_entities_by_archetype(archetype_name), to: EntityManager
  
  @doc """
  Get storage statistics and performance metrics.
  """
  def get_storage_stats do
    %{
      entity_stats: EntityManager.entity_stats(),
      component_stats: ComponentStorage.all_component_stats(),
      table_info: TableSupervisor.table_info(),
      performance_metrics: PerformanceMonitor.get_metrics()
    }
  end
  
  @doc """
  Create a backup of all storage data.
  """
  def create_backup(backup_path \\ nil) do
    TableSupervisor.create_backup(backup_path)
  end
  
  @doc """
  Restore storage from a backup.
  """
  def restore_backup(backup_path) do
    TableSupervisor.restore_backup(backup_path)
  end
  
  @doc """
  Trigger immediate sync to persistent storage.
  """
  def sync_to_persistent_storage do
    PersistenceBridge.sync_now()
  end
  
  @doc """
  Optimize storage performance.
  """
  def optimize do
    ComponentStorage.optimize_storage()
    EntityManager.cleanup_orphaned_entities()
  end
  
  @doc """
  Get a comprehensive storage health report.
  """
  def health_report do
    stats = get_storage_stats()
    performance_report = PerformanceMonitor.get_performance_report()
    
    %{
      timestamp: DateTime.utc_now(),
      overall_health: assess_overall_health(stats),
      statistics: stats,
      performance_report: performance_report,
      recommendations: generate_health_recommendations(stats, performance_report)
    }
  end
  
  # Private Functions
  
  defp assess_overall_health(stats) do
    issues = []
    
    # Check entity count
    issues = 
      if stats.entity_stats.total_entities > 50_000 do
        ["High entity count (#{stats.entity_stats.total_entities})" | issues]
      else
        issues
      end
    
    # Check memory usage
    total_memory = 
      stats.component_stats
      |> Enum.map(& &1.memory)
      |> Enum.sum()
    
    issues = 
      if total_memory > 1_000_000_000 do  # > 1GB
        ["High memory usage (#{total_memory} bytes)" | issues]
      else
        issues
      end
    
    # Check performance
    ops_per_second = stats.performance_metrics.operations_per_second
    issues = 
      if ops_per_second < 100 do
        ["Low operation throughput (#{ops_per_second} ops/sec)" | issues]
      else
        issues
      end
    
    case issues do
      [] -> :healthy
      [_] -> :warning
      [_, _] -> :warning
      _ -> :critical
    end
  end
  
  defp generate_health_recommendations(stats, performance_report) do
    recommendations = []
    
    # Memory recommendations
    total_memory = 
      stats.component_stats
      |> Enum.map(& &1.memory)
      |> Enum.sum()
    
    recommendations = 
      if total_memory > 500_000_000 do  # > 500MB
        ["Consider running optimization to reduce memory usage" | recommendations]
      else
        recommendations
      end
    
    # Entity recommendations
    recommendations = 
      if stats.entity_stats.total_entities > 10_000 do
        ["Consider implementing entity pooling for large entity counts" | recommendations]
      else
        recommendations
      end
    
    # Performance recommendations
    recommendations = performance_report.recommendations ++ recommendations
    
    case recommendations do
      [] -> ["Storage system is performing optimally"]
      _ -> recommendations
    end
  end
end