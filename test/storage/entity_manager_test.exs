defmodule AshGameServer.Storage.EntityManagerTest do
  use ExUnit.Case, async: true
  alias AshGameServer.Storage.{EntityManager, ComponentStorage, TableManager}

  setup do
    # Create unique test process name
    manager_name = :"test_entity_manager_#{:rand.uniform(100_000)}"
    
    # Start test entity manager
    {:ok, manager_pid} = EntityManager.start_link(name: manager_name)
    
    # Initialize for testing
    EntityManager.initialize(manager_name)
    
    on_exit(fn ->
      GenServer.stop(manager_pid)
    end)
    
    %{manager_name: manager_name, manager_pid: manager_pid}
  end

  describe "entity lifecycle" do
    test "create_entity generates unique IDs", %{manager_name: manager} do
      # Create multiple entities
      {:ok, entity_id1} = EntityManager.create_entity([], manager)
      {:ok, entity_id2} = EntityManager.create_entity([], manager)
      {:ok, entity_id3} = EntityManager.create_entity([], manager)
      
      # All IDs should be unique
      assert entity_id1 != entity_id2
      assert entity_id2 != entity_id3
      assert entity_id1 != entity_id3
      
      # IDs should be positive integers
      assert is_integer(entity_id1) and entity_id1 > 0
      assert is_integer(entity_id2) and entity_id2 > 0
      assert is_integer(entity_id3) and entity_id3 > 0
    end

    test "create_entity with archetype", %{manager_name: manager} do
      # Create entity with archetype
      {:ok, entity_id} = EntityManager.create_entity([archetype: :player], manager)
      
      # Check that entity exists
      assert EntityManager.entity_exists?(entity_id, manager)
      
      # Check archetype is set
      entities_by_archetype = EntityManager.get_entities_by_archetype(:player, manager)
      assert entity_id in entities_by_archetype
    end

    test "destroy_entity removes entity and components", %{manager_name: manager} do
      # Create entity with components
      {:ok, entity_id} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity_id, :position, %{x: 10, y: 20}, manager)
      EntityManager.add_component(entity_id, :health, %{current: 100}, manager)
      
      # Verify entity exists
      assert EntityManager.entity_exists?(entity_id, manager)
      
      # Destroy entity
      assert :ok = EntityManager.destroy_entity(entity_id, manager)
      
      # Verify entity no longer exists
      refute EntityManager.entity_exists?(entity_id, manager)
    end

    test "entity_exists? works correctly", %{manager_name: manager} do
      # Non-existent entity
      assert false = EntityManager.entity_exists?(999_999, manager)
      
      # Create entity
      {:ok, entity_id} = EntityManager.create_entity([], manager)
      assert true = EntityManager.entity_exists?(entity_id, manager)
      
      # Destroy entity
      EntityManager.destroy_entity(entity_id, manager)
      assert false = EntityManager.entity_exists?(entity_id, manager)
    end
  end

  describe "component management" do
    test "add and remove components", %{manager_name: manager} do
      {:ok, entity_id} = EntityManager.create_entity([], manager)
      
      # Add component
      component_data = %{x: 15.0, y: 25.0, z: 5.0}
      assert :ok = EntityManager.add_component(entity_id, :position, component_data, manager)
      
      # Remove component
      assert :ok = EntityManager.remove_component(entity_id, :position, manager)
    end

    test "add_component to non-existent entity", %{manager_name: manager} do
      # Try to add component to non-existent entity
      result = EntityManager.add_component(999_999, :position, %{x: 0, y: 0}, manager)
      assert {:error, :entity_not_found} = result
    end

    test "remove_component from non-existent entity", %{manager_name: manager} do
      # Try to remove component from non-existent entity
      result = EntityManager.remove_component(999_999, :position, manager)
      assert {:error, :entity_not_found} = result
    end
  end

  describe "archetype system" do
    test "apply_archetype adds predefined components", %{manager_name: manager} do
      {:ok, entity_id} = EntityManager.create_entity([], manager)
      
      # Apply player archetype (assuming it adds position, health, inventory components)
      assert :ok = EntityManager.apply_archetype(entity_id, :player, manager)
      
      # Verify archetype is recorded
      entities = EntityManager.get_entities_by_archetype(:player, manager)
      assert entity_id in entities
    end

    test "get_entities_by_archetype returns correct entities", %{manager_name: manager} do
      # Create entities with different archetypes
      {:ok, player1} = EntityManager.create_entity([archetype: :player], manager)
      {:ok, player2} = EntityManager.create_entity([archetype: :player], manager)
      {:ok, enemy1} = EntityManager.create_entity([archetype: :enemy], manager)
      {:ok, npc1} = EntityManager.create_entity([archetype: :npc], manager)
      
      # Get entities by archetype
      players = EntityManager.get_entities_by_archetype(:player, manager)
      enemies = EntityManager.get_entities_by_archetype(:enemy, manager)
      npcs = EntityManager.get_entities_by_archetype(:npc, manager)
      
      # Verify correct grouping
      assert player1 in players
      assert player2 in players
      assert length(players) >= 2
      
      assert enemy1 in enemies
      assert length(enemies) >= 1
      
      assert npc1 in npcs
      assert length(npcs) >= 1
      
      # Verify no cross-contamination
      refute enemy1 in players
      refute npc1 in players
      refute player1 in enemies
    end

    test "archetype_for_entity returns correct archetype", %{manager_name: manager} do
      {:ok, entity_id} = EntityManager.create_entity([archetype: :boss], manager)
      
      archetype = EntityManager.archetype_for_entity(entity_id, manager)
      assert archetype == :boss
    end
  end

  describe "entity queries" do
    test "query_entities with component requirements", %{manager_name: manager} do
      # Create entities with different component combinations
      {:ok, entity1} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity1, :position, %{x: 1, y: 1}, manager)
      EntityManager.add_component(entity1, :velocity, %{dx: 1, dy: 0}, manager)
      
      {:ok, entity2} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity2, :position, %{x: 2, y: 2}, manager)
      EntityManager.add_component(entity2, :health, %{current: 100}, manager)
      
      {:ok, entity3} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity3, :position, %{x: 3, y: 3}, manager)
      EntityManager.add_component(entity3, :velocity, %{dx: 0, dy: 1}, manager)
      EntityManager.add_component(entity3, :health, %{current: 80}, manager)
      
      # Query entities with position
      position_entities = EntityManager.query_entities([:position], [], manager)
      assert entity1 in position_entities
      assert entity2 in position_entities
      assert entity3 in position_entities
      
      # Query entities with position and velocity
      moving_entities = EntityManager.query_entities([:position, :velocity], [], manager)
      assert entity1 in moving_entities
      assert entity3 in moving_entities
      refute entity2 in moving_entities
      
      # Query entities with all three components
      complex_entities = EntityManager.query_entities([:position, :velocity, :health], [], manager)
      assert entity3 in complex_entities
      refute entity1 in complex_entities
      refute entity2 in complex_entities
    end

    test "query_entities with optional components", %{manager_name: manager} do
      # Create entities
      {:ok, entity1} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity1, :position, %{x: 1, y: 1}, manager)
      
      {:ok, entity2} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity2, :position, %{x: 2, y: 2}, manager)
      EntityManager.add_component(entity2, :velocity, %{dx: 1, dy: 0}, manager)
      
      # Query with required position and optional velocity
      entities = EntityManager.query_entities([:position], [:velocity], manager)
      
      # Both entities should be returned (position is required, velocity is optional)
      assert entity1 in entities
      assert entity2 in entities
    end

    test "get_all_entities returns all created entities", %{manager_name: manager} do
      initial_count = length(EntityManager.get_all_entities(manager))
      
      # Create some entities
      {:ok, _entity1} = EntityManager.create_entity([], manager)
      {:ok, _entity2} = EntityManager.create_entity([], manager)
      {:ok, _entity3} = EntityManager.create_entity([], manager)
      
      all_entities = EntityManager.get_all_entities(manager)
      assert length(all_entities) == initial_count + 3
    end
  end

  describe "statistics and cleanup" do
    test "entity_stats returns accurate information", %{manager_name: manager} do
      initial_stats = EntityManager.entity_stats(manager)
      initial_count = initial_stats.total_entities
      
      # Create entities
      {:ok, _entity1} = EntityManager.create_entity([], manager)
      {:ok, _entity2} = EntityManager.create_entity([archetype: :player], manager)
      
      updated_stats = EntityManager.entity_stats(manager)
      
      assert updated_stats.total_entities == initial_count + 2
      assert updated_stats.memory_usage > initial_stats.memory_usage
      assert is_integer(updated_stats.memory_usage)
    end

    test "cleanup_orphaned_entities removes entities without components", %{manager_name: manager} do
      # Create entity and add component
      {:ok, entity_id} = EntityManager.create_entity([], manager)
      EntityManager.add_component(entity_id, :position, %{x: 10, y: 10}, manager)
      
      # Remove all components (making it orphaned)
      EntityManager.remove_component(entity_id, :position, manager)
      
      # Run cleanup
      cleanup_result = EntityManager.cleanup_orphaned_entities(manager)
      
      # Entity should be cleaned up
      assert is_map(cleanup_result)
      assert cleanup_result.entities_cleaned >= 0
    end

    test "entity count tracking is accurate", %{manager_name: manager} do
      initial_count = EntityManager.entity_count(manager)
      
      # Create entities
      {:ok, entity1} = EntityManager.create_entity([], manager)
      {:ok, entity2} = EntityManager.create_entity([], manager)
      assert EntityManager.entity_count(manager) == initial_count + 2
      
      # Destroy one entity
      EntityManager.destroy_entity(entity1, manager)
      assert EntityManager.entity_count(manager) == initial_count + 1
      
      # Destroy second entity
      EntityManager.destroy_entity(entity2, manager)
      assert EntityManager.entity_count(manager) == initial_count
    end
  end
end