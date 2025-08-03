defmodule AshGameServer.Examples.StorageDemo do
  @moduledoc """
  Demonstration of the ETS storage system capabilities.
  
  This module shows how to use the storage system for game entities
  and components with high performance.
  """
  
  alias AshGameServer.Storage
  alias AshGameServer.Examples.SimpleGame
  require Logger
  
  @doc """
  Run a comprehensive storage demonstration.
  """
  def run_demo do
    Logger.info("=== Storage System Demo ===")
    
    # Initialize storage with example components
    component_definitions = SimpleGame.example_components()
    Storage.initialize(component_definitions)
    
    # Demo 1: Basic entity operations
    demo_basic_operations()
    
    # Demo 2: Batch operations and queries
    demo_batch_operations()
    
    # Demo 3: Performance testing
    demo_performance()
    
    # Demo 4: Storage statistics
    demo_statistics()
    
    Logger.info("=== Demo Complete ===")
  end
  
  defp demo_basic_operations do
    Logger.info("Demo 1: Basic Entity Operations")
    
    # Create a player entity
    {:ok, player_id} = Storage.create_entity(archetype: :player)
    Logger.info("Created player entity: #{player_id}")
    
    # Add custom components
    Storage.add_component(player_id, :position, %{x: 10.0, y: 20.0, z: 0.0})
    Storage.add_component(player_id, :velocity, %{dx: 1.0, dy: 0.0, dz: 0.0})
    
    # Retrieve components
    {:ok, position} = Storage.get_component(player_id, :position)
    Logger.info("Player position: #{inspect(position)}")
    
    # Check component existence
    has_health = Storage.has_component?(player_id, :health)
    Logger.info("Player has health component: #{has_health}")
    
    # Create an enemy entity
    {:ok, enemy_id} = Storage.create_entity(archetype: :enemy)
    Logger.info("Created enemy entity: #{enemy_id}")
    
    Logger.info("Basic operations completed\n")
  end
  
  defp demo_batch_operations do
    Logger.info("Demo 2: Batch Operations and Queries")
    
    # Create multiple entities
    entity_ids = 
      for i <- 1..5 do
        archetype = if rem(i, 2) == 0, do: :player, else: :enemy
        {:ok, entity_id} = Storage.create_entity(archetype: archetype)
        
        # Add position components to all
        Storage.add_component(entity_id, :position, %{
          x: :rand.uniform(100) * 1.0,
          y: :rand.uniform(100) * 1.0,
          z: 0.0
        })
        
        entity_id
      end
    
    Logger.info("Created #{length(entity_ids)} entities")
    
    # Query entities with position components
    entities_with_position = Storage.query_entities([:position])
    Logger.info("Entities with position: #{length(entities_with_position)}")
    
    # Query by archetype
    players = Storage.get_entities_by_archetype(:player)
    enemies = Storage.get_entities_by_archetype(:enemy)
    Logger.info("Players: #{length(players)}, Enemies: #{length(enemies)}")
    
    # Get multiple components for first entity
    first_entity = List.first(entity_ids)
    components = Storage.get_components(first_entity, [:position, :health, :inventory])
    Logger.info("Entity #{first_entity} components: #{inspect(Map.keys(components))}")
    
    Logger.info("Batch operations completed\n")
  end
  
  defp demo_performance do
    Logger.info("Demo 3: Performance Testing")
    
    # Create many entities quickly
    start_time = System.monotonic_time(:microsecond)
    
    entity_count = 1000
    entity_ids = 
      for _i <- 1..entity_count do
        {:ok, entity_id} = Storage.create_entity()
        
        # Add components
        Storage.add_component(entity_id, :position, %{
          x: :rand.uniform(1000) * 1.0,
          y: :rand.uniform(1000) * 1.0,
          z: 0.0
        })
        
        entity_id
      end
    
    creation_time = System.monotonic_time(:microsecond) - start_time
    Logger.info("Created #{entity_count} entities in #{creation_time / 1000} ms")
    
    # Test read performance
    read_start = System.monotonic_time(:microsecond)
    
    Enum.each(entity_ids, fn entity_id ->
      Storage.get_component(entity_id, :position)
    end)
    
    read_time = System.monotonic_time(:microsecond) - read_start
    Logger.info("Read #{entity_count} components in #{read_time / 1000} ms")
    Logger.info("Average read time: #{read_time / entity_count} microseconds")
    
    # Test query performance
    query_start = System.monotonic_time(:microsecond)
    entities_with_position = Storage.query_entities([:position])
    query_time = System.monotonic_time(:microsecond) - query_start
    
    Logger.info("Queried #{length(entities_with_position)} entities in #{query_time / 1000} ms")
    
    Logger.info("Performance testing completed\n")
  end
  
  defp demo_statistics do
    Logger.info("Demo 4: Storage Statistics")
    
    # Get comprehensive statistics
    stats = Storage.get_storage_stats()
    
    Logger.info("Entity Statistics:")
    Logger.info("  Total entities: #{stats.entity_stats.total_entities}")
    Logger.info("  Memory usage: #{stats.entity_stats.memory_usage} words")
    
    Logger.info("Component Statistics:")
    Enum.each(stats.component_stats, fn component_stat ->
      Logger.info("  #{component_stat.name}: #{component_stat.size} instances, #{component_stat.memory} words")
    end)
    
    Logger.info("Performance Metrics:")
    metrics = stats.performance_metrics
    Logger.info("  Total operations: #{metrics.total_operations}")
    Logger.info("  Operations/second: #{Float.round(metrics.operations_per_second, 2)}")
    Logger.info("  Uptime: #{metrics.uptime_ms} ms")
    
    # Get health report
    health_report = Storage.health_report()
    Logger.info("Overall Health: #{health_report.overall_health}")
    
    if length(health_report.recommendations) > 0 do
      Logger.info("Recommendations:")
      Enum.each(health_report.recommendations, fn rec ->
        Logger.info("  - #{rec}")
      end)
    end
    
    Logger.info("Statistics completed\n")
  end
  
  @doc """
  Demonstrate storage backup and restore.
  """
  def demo_backup_restore do
    Logger.info("=== Backup & Restore Demo ===")
    
    # Create some test data
    {:ok, entity_id} = Storage.create_entity(archetype: :player)
    Storage.add_component(entity_id, :position, %{x: 100.0, y: 200.0, z: 0.0})
    
    # Create backup
    {:ok, backup_path} = Storage.create_backup()
    Logger.info("Created backup: #{backup_path}")
    
    # Destroy entity
    Storage.destroy_entity(entity_id)
    Logger.info("Destroyed entity #{entity_id}")
    
    # Verify entity is gone
    case Storage.get_component(entity_id, :position) do
      {:error, :not_found} ->
        Logger.info("Confirmed entity is destroyed")
        
      {:ok, _data} ->
        Logger.error("Entity still exists after destruction!")
    end
    
    # Restore from backup
    Storage.restore_backup(backup_path)
    Logger.info("Restored from backup")
    
    # Verify entity is back
    case Storage.get_component(entity_id, :position) do
      {:ok, data} ->
        Logger.info("Entity restored with position: #{inspect(data)}")
        
      {:error, :not_found} ->
        Logger.error("Entity not found after restore!")
    end
    
    Logger.info("=== Backup & Restore Demo Complete ===")
  end
end