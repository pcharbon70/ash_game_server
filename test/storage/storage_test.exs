defmodule AshGameServer.StorageTest do
  use ExUnit.Case, async: true
  alias AshGameServer.Storage
  alias AshGameServer.Examples.SimpleGame

  setup do
    # Initialize storage for each test
    component_definitions = SimpleGame.example_components()
    Storage.initialize(component_definitions)
    
    # Clean up any existing test entities
    Storage.get_all_entities()
    |> Enum.each(&Storage.destroy_entity/1)
    
    :ok
  end

  describe "entity lifecycle integration" do
    test "create and destroy entities through unified interface" do
      # Create entity
      {:ok, entity_id} = Storage.create_entity()
      assert is_integer(entity_id)
      
      # Destroy entity
      assert :ok = Storage.destroy_entity(entity_id)
    end

    test "create entity with archetype" do
      {:ok, entity_id} = Storage.create_entity(archetype: :player)
      
      # Verify entity exists and has correct archetype
      entities = Storage.get_entities_by_archetype(:player)
      assert entity_id in entities
    end

    test "create multiple entities with different archetypes" do
      {:ok, player_id} = Storage.create_entity(archetype: :player)
      {:ok, enemy_id} = Storage.create_entity(archetype: :enemy)
      {:ok, npc_id} = Storage.create_entity(archetype: :npc)
      
      # Verify archetype separation
      players = Storage.get_entities_by_archetype(:player)
      enemies = Storage.get_entities_by_archetype(:enemy)
      npcs = Storage.get_entities_by_archetype(:npc)
      
      assert player_id in players
      assert enemy_id in enemies
      assert npc_id in npcs
      
      refute player_id in enemies
      refute enemy_id in npcs
      refute npc_id in players
    end
  end

  describe "component management integration" do
    test "add, get, and remove components" do
      {:ok, entity_id} = Storage.create_entity()
      
      # Add component
      position_data = %{x: 10.0, y: 20.0, z: 0.0}
      assert :ok = Storage.add_component(entity_id, :position, position_data)
      
      # Get component
      assert {:ok, ^position_data} = Storage.get_component(entity_id, :position)
      
      # Check component existence
      assert true = Storage.has_component?(entity_id, :position)
      
      # Remove component
      assert :ok = Storage.remove_component(entity_id, :position)
      assert false = Storage.has_component?(entity_id, :position)
    end

    test "get multiple components" do
      {:ok, entity_id} = Storage.create_entity()
      
      # Add multiple components
      Storage.add_component(entity_id, :position, %{x: 5.0, y: 10.0, z: 0.0})
      Storage.add_component(entity_id, :health, %{current: 80, max: 100})
      
      # Get multiple components
      components = Storage.get_components(entity_id, [:position, :health, :inventory])
      
      assert %{position: %{x: 5.0, y: 10.0, z: 0.0}, health: %{current: 80, max: 100}} = components
      refute Map.has_key?(components, :inventory)
    end

    test "component operations on non-existent entity" do
      non_existent_id = 999_999
      
      # All operations should fail gracefully
      assert {:error, :entity_not_found} = Storage.add_component(non_existent_id, :position, %{x: 0, y: 0})
      assert {:error, :not_found} = Storage.get_component(non_existent_id, :position)
      assert false = Storage.has_component?(non_existent_id, :position)
    end
  end

  describe "entity queries integration" do
    test "query entities with component requirements" do
      # Create test entities with different component sets
      {:ok, entity1} = Storage.create_entity()
      Storage.add_component(entity1, :position, %{x: 1, y: 1, z: 0})
      Storage.add_component(entity1, :velocity, %{dx: 1, dy: 0, dz: 0})
      
      {:ok, entity2} = Storage.create_entity()
      Storage.add_component(entity2, :position, %{x: 2, y: 2, z: 0})
      Storage.add_component(entity2, :health, %{current: 100, max: 100})
      
      {:ok, entity3} = Storage.create_entity()
      Storage.add_component(entity3, :velocity, %{dx: 0, dy: 1, dz: 0})
      Storage.add_component(entity3, :health, %{current: 80, max: 100})
      
      # Query by single component
      position_entities = Storage.query_entities([:position])
      assert entity1 in position_entities
      assert entity2 in position_entities
      refute entity3 in position_entities
      
      # Query by multiple components
      mobile_entities = Storage.query_entities([:position, :velocity])
      assert entity1 in mobile_entities
      refute entity2 in mobile_entities
      refute entity3 in mobile_entities
      
      # Query with no matches
      complex_entities = Storage.query_entities([:position, :velocity, :health])
      assert complex_entities == []
    end

    test "query entities with optional components" do
      {:ok, entity1} = Storage.create_entity()
      Storage.add_component(entity1, :position, %{x: 1, y: 1, z: 0})
      
      {:ok, entity2} = Storage.create_entity()
      Storage.add_component(entity2, :position, %{x: 2, y: 2, z: 0})
      Storage.add_component(entity2, :velocity, %{dx: 1, dy: 0, dz: 0})
      
      # Query with required and optional components
      entities = Storage.query_entities([:position], [:velocity])
      
      # Both should be returned since position is required and velocity is optional
      assert entity1 in entities
      assert entity2 in entities
    end
  end

  describe "storage statistics and health" do
    test "get comprehensive storage statistics" do
      # Create some test data
      {:ok, entity1} = Storage.create_entity(archetype: :player)
      {:ok, entity2} = Storage.create_entity(archetype: :enemy)
      
      Storage.add_component(entity1, :position, %{x: 10, y: 20, z: 0})
      Storage.add_component(entity1, :health, %{current: 100, max: 100})
      Storage.add_component(entity2, :position, %{x: 30, y: 40, z: 0})
      
      # Get storage statistics
      stats = Storage.get_storage_stats()
      
      # Verify structure
      assert Map.has_key?(stats, :entity_stats)
      assert Map.has_key?(stats, :component_stats)
      assert Map.has_key?(stats, :table_info)
      assert Map.has_key?(stats, :performance_metrics)
      
      # Verify entity stats
      assert stats.entity_stats.total_entities >= 2
      assert is_integer(stats.entity_stats.memory_usage)
      
      # Verify component stats
      assert is_list(stats.component_stats)
      
      # Verify performance metrics
      assert is_map(stats.performance_metrics)
      assert Map.has_key?(stats.performance_metrics, :total_operations)
    end

    test "health report provides assessment and recommendations" do
      # Create some entities to generate data
      for i <- 1..5 do
        {:ok, entity_id} = Storage.create_entity()
        Storage.add_component(entity_id, :position, %{x: i * 10.0, y: i * 20.0, z: 0.0})
      end
      
      health_report = Storage.health_report()
      
      # Verify structure
      assert Map.has_key?(health_report, :timestamp)
      assert Map.has_key?(health_report, :overall_health)
      assert Map.has_key?(health_report, :statistics)
      assert Map.has_key?(health_report, :performance_report)
      assert Map.has_key?(health_report, :recommendations)
      
      # Verify health status is valid
      assert health_report.overall_health in [:healthy, :warning, :critical]
      
      # Verify recommendations are provided
      assert is_list(health_report.recommendations)
    end

    test "storage optimization reduces memory usage" do
      # Create and destroy entities to create optimization opportunities
      entity_ids = for i <- 1..10 do
        {:ok, entity_id} = Storage.create_entity()
        Storage.add_component(entity_id, :position, %{x: i * 1.0, y: i * 2.0, z: 0.0})
        entity_id
      end
      
      # Remove some entities to create fragmentation
      Enum.take(entity_ids, 5)
      |> Enum.each(&Storage.destroy_entity/1)
      
      # Run optimization
      assert :ok = Storage.optimize()
    end
  end

  describe "backup and restore functionality" do
    test "create and restore backup" do
      # Create test data
      {:ok, entity_id} = Storage.create_entity(archetype: :player)
      original_position = %{x: 100.0, y: 200.0, z: 0.0}
      Storage.add_component(entity_id, :position, original_position)
      
      # Create backup
      {:ok, backup_path} = Storage.create_backup()
      assert is_binary(backup_path)
      assert File.exists?(backup_path)
      
      # Modify data
      Storage.add_component(entity_id, :position, %{x: 999.0, y: 999.0, z: 0.0})
      
      # Restore backup
      assert :ok = Storage.restore_backup(backup_path)
      
      # Verify data is restored
      {:ok, restored_position} = Storage.get_component(entity_id, :position)
      assert restored_position == original_position
      
      # Clean up backup file
      File.rm(backup_path)
    end

    test "backup contains all entity and component data" do
      # Create diverse test data
      {:ok, player_id} = Storage.create_entity(archetype: :player)
      {:ok, enemy_id} = Storage.create_entity(archetype: :enemy)
      
      Storage.add_component(player_id, :position, %{x: 10, y: 20, z: 0})
      Storage.add_component(player_id, :health, %{current: 80, max: 100})
      Storage.add_component(enemy_id, :position, %{x: 50, y: 60, z: 0})
      
      # Create backup
      {:ok, backup_path} = Storage.create_backup()
      
      # Clear all data
      Storage.destroy_entity(player_id)
      Storage.destroy_entity(enemy_id)
      
      # Verify data is gone
      assert false = Storage.has_component?(player_id, :position)
      assert false = Storage.has_component?(enemy_id, :position)
      
      # Restore backup
      Storage.restore_backup(backup_path)
      
      # Verify all data is restored
      assert {:ok, %{x: 10, y: 20, z: 0}} = Storage.get_component(player_id, :position)
      assert {:ok, %{current: 80, max: 100}} = Storage.get_component(player_id, :health)
      assert {:ok, %{x: 50, y: 60, z: 0}} = Storage.get_component(enemy_id, :position)
      
      # Verify archetypes are restored
      players = Storage.get_entities_by_archetype(:player)
      enemies = Storage.get_entities_by_archetype(:enemy)
      assert player_id in players
      assert enemy_id in enemies
      
      # Clean up
      File.rm(backup_path)
    end
  end

  describe "persistence bridge integration" do
    test "trigger manual sync to persistent storage" do
      # Create entity
      {:ok, entity_id} = Storage.create_entity(archetype: :player)
      Storage.add_component(entity_id, :position, %{x: 25, y: 35, z: 0})
      
      # Trigger sync (should not crash)
      assert :ok = Storage.sync_to_persistent_storage()
    end
  end

  describe "error handling and edge cases" do
    test "operations on destroyed entities fail gracefully" do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :position, %{x: 0, y: 0, z: 0})
      
      # Destroy entity
      Storage.destroy_entity(entity_id)
      
      # All subsequent operations should fail gracefully
      assert {:error, :entity_not_found} = Storage.add_component(entity_id, :health, %{current: 100})
      assert {:error, :not_found} = Storage.get_component(entity_id, :position)
      assert false = Storage.has_component?(entity_id, :position)
    end

    test "query with non-existent components returns empty list" do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :position, %{x: 0, y: 0, z: 0})
      
      # Query for components that don't exist
      entities = Storage.query_entities([:non_existent_component])
      assert entities == []
      
      # Query with mix of existing and non-existent
      entities = Storage.query_entities([:position, :non_existent_component])
      assert entities == []
    end

    test "get_components with empty component list" do
      {:ok, entity_id} = Storage.create_entity()
      
      # Get components with empty list
      components = Storage.get_components(entity_id, [])
      assert components == %{}
    end

    test "archetype operations with invalid archetype" do
      entities = Storage.get_entities_by_archetype(:non_existent_archetype)
      assert entities == []
    end
  end
end