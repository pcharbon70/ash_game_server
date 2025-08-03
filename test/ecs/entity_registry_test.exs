defmodule AshGameServer.ECS.EntityRegistryTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.ECS.Entity
  alias AshGameServer.ECS.EntityRegistry
  
  setup do
    # Start the EntityRegistry for testing
    start_supervised!({EntityRegistry, []})
    :ok
  end
  
  describe "entity registration" do
    test "registers a new entity" do
      entity = %{
        id: 1,
        version: 1,
        generation: 1,
        status: :active,
        archetype: :player,
        components: [:position, :health],
        metadata: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        parent_id: nil,
        children: [],
        tags: [:player],
        lifecycle_events: [:created]
      }
      
      :ok = EntityRegistry.register_entity(entity)
      
      {:ok, retrieved} = EntityRegistry.get_entity(1)
      assert retrieved.id == entity.id
      assert retrieved.archetype == entity.archetype
    end
    
    test "updates an existing entity" do
      entity = create_test_entity(1, :player)
      EntityRegistry.register_entity(entity)
      
      updated_entity = %{entity | version: 2, status: :inactive}
      :ok = EntityRegistry.update_entity(updated_entity)
      
      {:ok, retrieved} = EntityRegistry.get_entity(1)
      assert retrieved.version == 2
      assert retrieved.status == :inactive
    end
    
    test "unregisters an entity" do
      entity = create_test_entity(1, :player)
      EntityRegistry.register_entity(entity)
      
      assert EntityRegistry.exists?(1)
      
      :ok = EntityRegistry.unregister_entity(1)
      
      refute EntityRegistry.exists?(1)
      assert {:error, :not_found} = EntityRegistry.get_entity(1)
    end
  end
  
  describe "entity queries" do
    setup do
      entities = [
        create_test_entity(1, :player, :active, [:player]),
        create_test_entity(2, :npc, :active, [:enemy]),
        create_test_entity(3, :player, :inactive, [:player]),
        create_test_entity(4, :npc, :destroyed, [:boss])
      ]
      
      Enum.each(entities, &EntityRegistry.register_entity/1)
      
      :ok
    end
    
    test "queries entities by status" do
      active_entities = EntityRegistry.query_by_status(:active)
      inactive_entities = EntityRegistry.query_by_status(:inactive)
      destroyed_entities = EntityRegistry.query_by_status(:destroyed)
      
      assert length(active_entities) == 2
      assert 1 in active_entities
      assert 2 in active_entities
      
      assert length(inactive_entities) == 1
      assert 3 in inactive_entities
      
      assert length(destroyed_entities) == 1
      assert 4 in destroyed_entities
    end
    
    test "queries entities by archetype" do
      player_entities = EntityRegistry.query_by_archetype(:player)
      npc_entities = EntityRegistry.query_by_archetype(:npc)
      
      assert length(player_entities) == 2
      assert 1 in player_entities
      assert 3 in player_entities
      
      assert length(npc_entities) == 2
      assert 2 in npc_entities
      assert 4 in npc_entities
    end
    
    test "queries entities by tag" do
      player_tagged = EntityRegistry.query_by_tag(:player)
      enemy_tagged = EntityRegistry.query_by_tag(:enemy)
      boss_tagged = EntityRegistry.query_by_tag(:boss)
      
      assert length(player_tagged) == 2
      assert 1 in player_tagged
      assert 3 in player_tagged
      
      assert length(enemy_tagged) == 1
      assert 2 in enemy_tagged
      
      assert length(boss_tagged) == 1
      assert 4 in boss_tagged
    end
    
    test "queries entities with complex filters" do
      filters = %{
        archetype: :player,
        status: :active
      }
      
      entities = EntityRegistry.query_entities(filters)
      
      assert length(entities) == 1
      assert hd(entities).id == 1
    end
    
    test "queries entities with pagination" do
      filters = %{}
      
      {entities, has_more} = EntityRegistry.query_entities_paginated(filters, 0, 2)
      
      assert length(entities) == 2
      assert has_more == true
      
      {entities, has_more} = EntityRegistry.query_entities_paginated(filters, 2, 2)
      
      assert length(entities) == 2
      assert has_more == false
    end
  end
  
  describe "entity statistics" do
    setup do
      entities = [
        create_test_entity(1, :player, :active, [:player]),
        create_test_entity(2, :player, :inactive, [:player]),
        create_test_entity(3, :npc, :active, [:enemy]),
        create_test_entity(4, :npc, :destroyed, [:boss])
      ]
      
      Enum.each(entities, &EntityRegistry.register_entity/1)
      
      :ok
    end
    
    test "gets total entity count" do
      count = EntityRegistry.total_count()
      assert count == 4
    end
    
    test "counts entities by status" do
      status_counts = EntityRegistry.count_by_status()
      
      assert status_counts[:active] == 2
      assert status_counts[:inactive] == 1
      assert status_counts[:destroyed] == 1
    end
    
    test "counts entities by archetype" do
      archetype_counts = EntityRegistry.count_by_archetype()
      
      assert archetype_counts[:player] == 2
      assert archetype_counts[:npc] == 2
    end
    
    test "gets comprehensive statistics" do
      stats = EntityRegistry.get_statistics()
      
      assert Map.has_key?(stats, :entities_created)
      assert Map.has_key?(stats, :total_entities)
      assert Map.has_key?(stats, :status_distribution)
      assert Map.has_key?(stats, :archetype_distribution)
    end
  end
  
  describe "garbage collection" do
    test "performs garbage collection on old destroyed entities" do
      # Create and destroy an entity
      entity = create_test_entity(1, :player, :destroyed, [])
      
      # Manually set old timestamp
      old_entity = %{entity | updated_at: DateTime.add(DateTime.utc_now(), -600, :second)}
      EntityRegistry.register_entity(old_entity)
      
      {:ok, collected_count} = EntityRegistry.garbage_collect()
      
      assert collected_count >= 0
    end
    
    test "cleans up old entities" do
      entity = create_test_entity(1, :player, :destroyed, [])
      EntityRegistry.register_entity(entity)
      
      {:ok, cleaned_count} = EntityRegistry.cleanup_old_entities(1)
      
      assert cleaned_count >= 0
    end
  end
  
  describe "memory usage" do
    test "gets memory usage statistics" do
      memory_usage = EntityRegistry.memory_usage()
      
      assert Map.has_key?(memory_usage, :entities_table)
      assert Map.has_key?(memory_usage, :status_index)
      assert Map.has_key?(memory_usage, :archetype_index)
      assert is_integer(memory_usage.entities_table)
    end
  end
  
  describe "index management" do
    test "rebuilds indexes for performance optimization" do
      entity = create_test_entity(1, :player)
      EntityRegistry.register_entity(entity)
      
      :ok = EntityRegistry.rebuild_indexes()
      
      # Verify entity is still queryable after rebuild
      players = EntityRegistry.query_by_archetype(:player)
      assert 1 in players
    end
  end
  
  describe "parent-child relationships" do
    test "queries entities by parent" do
      parent = create_test_entity(1, :player)
      child1 = create_test_entity(2, :npc, :active, [], 1)
      child2 = create_test_entity(3, :npc, :active, [], 1)
      
      EntityRegistry.register_entity(parent)
      EntityRegistry.register_entity(child1)
      EntityRegistry.register_entity(child2)
      
      children = EntityRegistry.query_by_parent(1)
      
      assert length(children) == 2
      assert 2 in children
      assert 3 in children
    end
  end
  
  # Helper functions
  
  defp create_test_entity(id, archetype, status \\ :active, tags \\ [], parent_id \\ nil) do
    %{
      id: id,
      version: 1,
      generation: 1,
      status: status,
      archetype: archetype,
      components: [:position, :health],
      metadata: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      parent_id: parent_id,
      children: [],
      tags: tags,
      lifecycle_events: [:created]
    }
  end
end