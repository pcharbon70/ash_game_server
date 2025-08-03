defmodule AshGameServer.ECS.EntityTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.ECS.Entity
  alias AshGameServer.ECS.EntityRegistry
  
  setup do
    # Start the EntityRegistry for testing
    start_supervised!({EntityRegistry, []})
    :ok
  end
  
  describe "ID generation" do
    test "generates incremental IDs" do
      id1 = Entity.generate_id(:incremental)
      id2 = Entity.generate_id(:incremental)
      
      assert is_integer(id1)
      assert is_integer(id2)
      assert id2 > id1
    end
    
    test "generates UUID IDs" do
      id = Entity.generate_id(:uuid)
      
      assert is_binary(id)
      assert String.length(id) == 36  # Standard UUID length
    end
    
    test "generates snowflake IDs" do
      id = Entity.generate_id(:snowflake)
      
      assert is_integer(id)
      assert id > 0
    end
    
    test "generates pooled IDs when pool is available" do
      # Configure pooling
      Entity.configure_pooling(%{
        pool_size: 100,
        prealloc_count: 10,
        max_pool_size: 1000,
        gc_interval: 60_000
      })
      
      id = Entity.generate_id(:pooled)
      assert is_integer(id)
    end
  end
  
  describe "entity lifecycle" do
    test "creates a new entity with default options" do
      {:ok, entity} = Entity.create()
      
      assert entity.id != nil
      assert entity.version == 1
      assert entity.generation == 1
      assert entity.status == :active
      assert entity.archetype == nil
      assert entity.components == []
      assert entity.children == []
      assert entity.tags == []
      assert entity.lifecycle_events == [:created]
    end
    
    test "creates an entity with custom options" do
      opts = [
        archetype: :player,
        metadata: %{server_id: "server1"},
        tags: [:player, :human],
        parent_id: 123
      ]
      
      {:ok, entity} = Entity.create(opts)
      
      assert entity.archetype == :player
      assert entity.metadata.server_id == "server1"
      assert entity.tags == [:player, :human]
      assert entity.parent_id == 123
    end
    
    test "updates entity metadata" do
      {:ok, entity} = Entity.create()
      
      {:ok, updated} = Entity.update(entity.id, metadata: %{level: 10})
      
      assert updated.metadata.level == 10
      assert updated.version == entity.version + 1
      assert updated.updated_at != entity.updated_at
    end
    
    test "updates entity status with lifecycle events" do
      {:ok, entity} = Entity.create()
      
      {:ok, updated} = Entity.update(entity.id, status: :inactive)
      
      assert updated.status == :inactive
      assert :deactivated in updated.lifecycle_events
      assert updated.version == entity.version + 1
    end
    
    test "destroys an entity" do
      {:ok, entity} = Entity.create()
      
      :ok = Entity.destroy(entity.id)
      
      {:ok, destroyed} = EntityRegistry.get_entity(entity.id)
      assert destroyed.status == :destroyed
      assert :destroyed in destroyed.lifecycle_events
    end
    
    test "activates a pooled entity" do
      {:ok, entity} = Entity.create()
      Entity.update(entity.id, status: :pooled)
      
      {:ok, activated} = Entity.activate(entity.id)
      
      assert activated.status == :active
      assert activated.generation == entity.generation + 1
      assert :activated in activated.lifecycle_events
    end
    
    test "deactivates an entity" do
      {:ok, entity} = Entity.create()
      
      {:ok, deactivated} = Entity.deactivate(entity.id)
      
      assert deactivated.status == :inactive
      assert :deactivated in deactivated.lifecycle_events
    end
  end
  
  describe "versioning" do
    test "gets current entity version" do
      {:ok, entity} = Entity.create()
      
      {:ok, version} = Entity.get_version(entity.id)
      assert version == entity.version
    end
    
    test "checks if version is current" do
      {:ok, entity} = Entity.create()
      
      assert Entity.version_current?(entity.id, entity.version)
      refute Entity.version_current?(entity.id, entity.version - 1)
    end
    
    test "version increments on updates" do
      {:ok, entity} = Entity.create()
      initial_version = entity.version
      
      Entity.update(entity.id, metadata: %{test: true})
      {:ok, new_version} = Entity.get_version(entity.id)
      
      assert new_version == initial_version + 1
    end
  end
  
  describe "metadata management" do
    test "sets entity metadata" do
      {:ok, entity} = Entity.create()
      metadata = %{level: 5, class: "warrior"}
      
      {:ok, updated} = Entity.set_metadata(entity.id, metadata)
      
      assert updated.metadata == metadata
    end
    
    test "gets entity metadata" do
      {:ok, entity} = Entity.create(metadata: %{level: 10})
      
      {:ok, metadata} = Entity.get_metadata(entity.id)
      
      assert metadata.level == 10
    end
    
    test "adds tags to entity" do
      {:ok, entity} = Entity.create()
      
      {:ok, updated} = Entity.add_tags(entity.id, [:player, :human])
      
      assert :player in updated.tags
      assert :human in updated.tags
    end
    
    test "checks if entity has tag" do
      {:ok, entity} = Entity.create(tags: [:player])
      
      assert Entity.has_tag?(entity.id, :player)
      refute Entity.has_tag?(entity.id, :npc)
    end
  end
  
  describe "lifecycle events" do
    test "tracks lifecycle events" do
      {:ok, entity} = Entity.create()
      
      {:ok, events} = Entity.get_lifecycle_events(entity.id)
      
      assert :created in events
    end
    
    test "adds events on status changes" do
      {:ok, entity} = Entity.create()
      Entity.update(entity.id, status: :inactive)
      Entity.update(entity.id, status: :active)
      
      {:ok, events} = Entity.get_lifecycle_events(entity.id)
      
      assert :created in events
      assert :deactivated in events
      assert :activated in events
    end
  end
  
  describe "error handling" do
    test "returns error for non-existent entity updates" do
      result = Entity.update(99_999, metadata: %{test: true})
      
      assert {:error, :not_found} = result
    end
    
    test "returns error for non-existent entity destruction" do
      result = Entity.destroy(99_999)
      
      assert {:error, :not_found} = result
    end
    
    test "returns error for invalid activation" do
      {:ok, entity} = Entity.create()  # Already active
      
      result = Entity.activate(entity.id)
      
      assert {:error, {:invalid_status, :active}} = result
    end
  end
end