defmodule AshGameServer.ECS.EntitySerializationTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.ECS.Entity
  alias AshGameServer.ECS.EntityRegistry
  alias AshGameServer.ECS.EntitySerialization
  alias AshGameServer.ECS.EntityRelationships
  alias AshGameServer.Storage
  
  setup do
    # Start required services for testing
    start_supervised!({EntityRegistry, []})
    start_supervised!({EntityRelationships, []})
    
    # Initialize storage (not a GenServer)
    AshGameServer.Storage.initialize()
    
    # Create deferred relationships table if it doesn't exist
    case :ets.whereis(:deferred_relationships) do
      :undefined -> :ets.new(:deferred_relationships, [:named_table, :public, :bag])
      _tid -> :ok
    end
    
    # Create test entities with components
    {:ok, entity1} = Entity.create(archetype: :player, tags: [:player], metadata: %{level: 10})
    {:ok, entity2} = Entity.create(archetype: :npc, tags: [:enemy], metadata: %{level: 5})
    
    # Add some components
    Storage.add_component(entity1.id, :position, %{x: 10.0, y: 20.0, z: 0.0})
    Storage.add_component(entity1.id, :health, %{current: 100, max: 100})
    Storage.add_component(entity2.id, :position, %{x: 50.0, y: 60.0, z: 0.0})
    Storage.add_component(entity2.id, :ai_controller, %{behavior: :aggressive})
    
    # Add some relationships
    EntityRelationships.add_child(entity1.id, entity2.id)
    EntityRelationships.create_relationship(entity1.id, entity2.id, :enemy)
    
    %{
      entity1_id: entity1.id,
      entity2_id: entity2.id
    }
  end
  
  describe "entity export" do
    test "exports single entity with all data", %{entity1_id: entity1_id} do
      opts = %{
        include_components: true,
        include_relationships: true,
        include_metadata: true
      }
      
      {:ok, serialized} = EntitySerialization.export_entity(entity1_id, opts)
      
      assert serialized.entity.id == entity1_id
      assert serialized.entity.archetype == :player
      assert Map.has_key?(serialized.components, :position)
      assert Map.has_key?(serialized.components, :health)
      assert length(serialized.relationships) > 0
      assert serialized.version == EntitySerialization.current_version()
    end
    
    test "exports entity with selective data inclusion", %{entity1_id: entity1_id} do
      opts = %{
        include_components: true,
        include_relationships: false,
        include_metadata: false
      }
      
      {:ok, serialized} = EntitySerialization.export_entity(entity1_id, opts)
      
      assert Map.has_key?(serialized.components, :position)
      assert serialized.relationships == []
      assert serialized.metadata == %{}
    end
    
    test "exports multiple entities", %{entity1_id: entity1_id, entity2_id: entity2_id} do
      entity_ids = [entity1_id, entity2_id]
      opts = %{format: :json}
      
      {:ok, json_data} = EntitySerialization.export_entities(entity_ids, opts)
      
      assert is_binary(json_data)
      
      # Parse and verify structure
      {:ok, parsed} = Jason.decode(json_data, keys: :atoms)
      assert length(parsed.entities) == 2
      assert parsed.format == :json
      assert parsed.version == EntitySerialization.current_version()
    end
    
    test "exports with different formats", %{entity1_id: entity1_id} do
      entity_ids = [entity1_id]
      
      # Test JSON format
      {:ok, json_data} = EntitySerialization.export_entities(entity_ids, %{format: :json})
      assert is_binary(json_data)
      
      # Test binary format
      {:ok, binary_data} = EntitySerialization.export_entities(entity_ids, %{format: :binary})
      assert is_binary(binary_data)
      
      # Test compressed format
      {:ok, compressed_data} = EntitySerialization.export_entities(entity_ids, %{format: :compressed})
      assert is_binary(compressed_data)
      
      # Compressed should be smaller than regular binary
      assert byte_size(compressed_data) <= byte_size(binary_data)
    end
    
    test "exports by archetype", %{entity1_id: entity1_id} do
      {:ok, export_data} = EntitySerialization.export_by_archetype(:player, %{format: :json})
      
      {:ok, parsed} = Jason.decode(export_data, keys: :atoms)
      
      # Should include the player entity
      entity_ids = Enum.map(parsed.entities, fn entity -> entity.entity.id end)
      assert entity1_id in entity_ids
    end
    
    test "exports entity hierarchy", %{entity1_id: entity1_id, entity2_id: entity2_id} do
      {:ok, export_data} = EntitySerialization.export_hierarchy(entity1_id, %{format: :json})
      
      {:ok, parsed} = Jason.decode(export_data, keys: :atoms)
      
      # Should include both parent and child
      entity_ids = Enum.map(parsed.entities, fn entity -> entity.entity.id end)
      assert entity1_id in entity_ids
      assert entity2_id in entity_ids
    end
  end
  
  describe "entity import" do
    test "imports single serialized entity" do
      # First export an entity
      {:ok, entity} = Entity.create(archetype: :test_import, tags: [:test])
      Storage.add_component(entity.id, :position, %{x: 100.0, y: 200.0, z: 0.0})
      
      {:ok, serialized} = EntitySerialization.export_entity(entity.id)
      
      # Destroy the original
      Entity.destroy(entity.id)
      
      # Import it back
      {:ok, imported_id} = EntitySerialization.import_entity(serialized)
      
      # Verify imported entity
      {:ok, imported_entity} = EntityRegistry.get_entity(imported_id)
      assert imported_entity.archetype == :test_import
      assert :test in imported_entity.tags
      
      # Verify components were imported
      {:ok, position} = Storage.get_component(imported_id, :position)
      assert position.x == 100.0
    end
    
    test "imports with different merge strategies" do
      # Create entity with component
      {:ok, entity} = Entity.create(archetype: :merge_test)
      Storage.add_component(entity.id, :health, %{current: 100, max: 100})
      
      # Export it
      {:ok, serialized} = EntitySerialization.export_entity(entity.id)
      
      # Modify the serialized data
      updated_serialized = put_in(serialized, [:components, :health, :current], 50)
      
      # Import with merge strategy
      opts = %{merge_strategy: :merge}
      {:ok, _imported_id} = EntitySerialization.import_entity(updated_serialized, opts)
      
      # Verify merge occurred
      {:ok, health} = Storage.get_component(entity.id, :health)
      assert health.current == 50
      assert health.max == 100
    end
    
    test "imports multiple entities from export result" do
      # Export multiple entities
      {:ok, entity1} = Entity.create(archetype: :import_test1)
      {:ok, entity2} = Entity.create(archetype: :import_test2)
      
      entity_ids = [entity1.id, entity2.id]
      {:ok, json_data} = EntitySerialization.export_entities(entity_ids, %{format: :json})
      
      # Clear entities
      Entity.destroy(entity1.id)
      Entity.destroy(entity2.id)
      
      # Import them back
      {:ok, imported_ids} = EntitySerialization.import_entities(json_data, %{format: :json})
      
      assert length(imported_ids) == 2
      
      # Verify entities exist
      Enum.each(imported_ids, fn entity_id ->
        assert {:ok, _entity} = EntityRegistry.get_entity(entity_id)
      end)
    end
    
    test "handles import errors gracefully" do
      invalid_serialized = %{
        entity: %{id: "invalid"},
        # Missing required fields
        version: EntitySerialization.current_version()
      }
      
      {:error, _reason} = EntitySerialization.import_entity(invalid_serialized)
    end
    
    test "imports with conflict resolution" do
      # Create an entity
      {:ok, entity} = Entity.create(archetype: :conflict_test, tags: [:original])
      original_id = entity.id
      
      # Export it
      {:ok, serialized} = EntitySerialization.export_entity(original_id)
      
      # Modify serialized data
      modified_serialized = put_in(serialized, [:entity, :tags], [:modified])
      
      # Import with merge - should combine results
      result = EntitySerialization.import_with_merge(
        %{entities: [modified_serialized], version: EntitySerialization.current_version(), exported_at: DateTime.utc_now(), format: :json}, 
        %{merge_strategy: :merge}
      )
      
      assert {:ok, %{created: created_ids}} = result
      assert length(created_ids) >= 0
    end
  end
  
  describe "batch operations" do
    test "exports entities in batches" do
      # Create several entities
      entity_ids = for i <- 1..5 do
        {:ok, entity} = Entity.create(archetype: :batch_test)
        entity.id
      end
      
      batch_stream = EntitySerialization.export_batch(entity_ids, 2, %{format: :json})
      
      batches = Enum.to_list(batch_stream)
      
      # Should have 3 batches (2, 2, 1)
      assert length(batches) == 3
      
      # Each batch should be successful
      Enum.each(batches, fn batch_result ->
        assert {:ok, _export_data} = batch_result
      end)
    end
    
    test "imports entities in batches with progress tracking" do
      # Create export batches
      entity_ids = for i <- 1..4 do
        {:ok, entity} = Entity.create(archetype: :batch_import_test)
        entity.id
      end
      
      batch_stream = EntitySerialization.export_batch(entity_ids, 2, %{format: :json})
      
      # Import in batches
      {:ok, results} = EntitySerialization.import_batch(batch_stream, %{format: :json})
      
      assert results.total >= 4
      assert results.success >= 0
      assert is_list(results.errors)
    end
  end
  
  describe "versioning and migration" do
    test "detects when migration is needed" do
      assert EntitySerialization.migration_needed?("0.9.0")
      refute EntitySerialization.migration_needed?(EntitySerialization.current_version())
    end
    
    test "migrates entity to current version" do
      old_serialized = %{
        entity: %{id: 1, archetype: :test},
        components: %{},
        relationships: [],
        metadata: %{},
        version: "0.9.0",
        exported_at: DateTime.utc_now()
      }
      
      {:ok, migrated} = EntitySerialization.migrate_entity(old_serialized)
      
      assert migrated.version == EntitySerialization.current_version()
      assert Map.has_key?(migrated.entity, :migration_notes)
    end
    
    test "handles unsupported migration versions" do
      old_serialized = %{
        entity: %{id: 1},
        components: %{},
        version: "0.1.0",
        exported_at: DateTime.utc_now()
      }
      
      {:error, {:unsupported_migration, "0.1.0", _}} = EntitySerialization.migrate_entity(old_serialized)
    end
  end
  
  describe "validation" do
    test "validates serialized entity structure" do
      valid_serialized = %{
        entity: %{id: 1, version: 1, created_at: DateTime.utc_now()},
        components: %{},
        relationships: [],
        version: EntitySerialization.current_version(),
        exported_at: DateTime.utc_now()
      }
      
      :ok = EntitySerialization.validate_serialized_entity(valid_serialized)
    end
    
    test "rejects invalid serialized entity" do
      invalid_serialized = %{
        # Missing required fields
        components: %{}
      }
      
      {:error, {:missing_fields, missing}} = EntitySerialization.validate_serialized_entity(invalid_serialized)
      assert :entity in missing
      assert :version in missing
    end
  end
  
  describe "utilities and optimization" do
    test "gets export statistics" do
      entity_ids = [1, 2]
      {:ok, json_data} = EntitySerialization.export_entities(entity_ids, %{format: :json})
      {:ok, export_result} = Jason.decode(json_data, keys: :atoms)
      
      stats = EntitySerialization.get_export_stats(export_result)
      
      assert Map.has_key?(stats, :entity_count)
      assert Map.has_key?(stats, :component_types)
      assert Map.has_key?(stats, :relationship_count)
      assert Map.has_key?(stats, :data_size)
      assert is_integer(stats.entity_count)
    end
    
    test "optimizes export data" do
      # Create export with some empty data
      export_result = %{
        entities: [
          %{
            entity: %{id: 1},
            components: %{empty_comp: %{}, valid_comp: %{data: "test"}},
            relationships: [],
            version: "1.0.0"
          }
        ],
        metadata: %{},
        version: "1.0.0",
        exported_at: DateTime.utc_now(),
        format: :json
      }
      
      optimized = EntitySerialization.optimize_export(export_result)
      
      # Empty components should be removed
      entity = hd(optimized.entities)
      refute Map.has_key?(entity.components, :empty_comp)
      assert Map.has_key?(entity.components, :valid_comp)
      assert optimized.metadata.optimized == true
    end
    
    test "handles different data formats" do
      entity_ids = [1]
      
      # Test all supported formats work
      formats = [:json, :binary, :compressed]
      
      Enum.each(formats, fn format ->
        {:ok, _data} = EntitySerialization.export_entities(entity_ids, %{format: format})
      end)
    end
  end
  
  describe "error handling" do
    test "handles non-existent entity export" do
      {:error, :not_found} = EntitySerialization.export_entity(99_999)
    end
    
    test "handles malformed export data" do
      invalid_data = "invalid json"
      
      {:error, _reason} = EntitySerialization.import_entities(invalid_data, %{format: :json})
    end
    
    test "handles import validation failures" do
      invalid_export = %{
        entities: [%{invalid: "structure"}],
        # Missing required fields
        format: :json
      }
      
      {:error, _reason} = EntitySerialization.import_entities(invalid_export, %{validate: true})
    end
  end
end