defmodule AshGameServer.ECS.EntityArchetypeTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.ECS.EntityArchetype
  alias AshGameServer.ECS.EntityRegistry
  alias AshGameServer.Storage
  
  setup do
    # Start required services for testing
    start_supervised!({EntityRegistry, []})
    start_supervised!({EntityArchetype, []})
    
    # Initialize storage (not a GenServer)
    AshGameServer.Storage.initialize()
    
    :ok
  end
  
  describe "archetype registration" do
    test "registers a new archetype" do
      archetype_def = create_test_archetype(:test_player)
      
      :ok = EntityArchetype.register_archetype(archetype_def)
      
      {:ok, retrieved} = EntityArchetype.get_archetype(:test_player)
      assert retrieved.name == :test_player
      assert length(retrieved.components) == 2
    end
    
    test "validates archetype definition on registration" do
      invalid_archetype = %{
        name: :invalid,
        # Missing required components field
        description: "Invalid archetype"
      }
      
      {:error, _reason} = EntityArchetype.register_archetype(invalid_archetype)
    end
    
    test "lists all registered archetypes" do
      archetype1 = create_test_archetype(:archetype1)
      archetype2 = create_test_archetype(:archetype2)
      
      EntityArchetype.register_archetype(archetype1)
      EntityArchetype.register_archetype(archetype2)
      
      archetypes = EntityArchetype.list_archetypes()
      
      assert :archetype1 in archetypes
      assert :archetype2 in archetypes
      # Built-in archetypes should also be present
      assert :player in archetypes
      assert :npc in archetypes
    end
    
    test "updates an existing archetype" do
      archetype_def = create_test_archetype(:test_update)
      EntityArchetype.register_archetype(archetype_def)
      
      updates = %{description: "Updated description"}
      :ok = EntityArchetype.update_archetype(:test_update, updates)
      
      {:ok, updated} = EntityArchetype.get_archetype(:test_update)
      assert updated.description == "Updated description"
    end
    
    test "removes an archetype" do
      archetype_def = create_test_archetype(:test_remove)
      EntityArchetype.register_archetype(archetype_def)
      
      :ok = EntityArchetype.remove_archetype(:test_remove)
      
      {:error, :not_found} = EntityArchetype.get_archetype(:test_remove)
    end
  end
  
  describe "entity spawning" do
    setup do
      archetype_def = create_test_archetype(:spawnable_player)
      EntityArchetype.register_archetype(archetype_def)
      :ok
    end
    
    test "spawns a single entity from archetype" do
      {:ok, entity_id} = EntityArchetype.spawn_entity(:spawnable_player)
      
      assert is_integer(entity_id) or is_binary(entity_id)
      
      {:ok, entity} = EntityRegistry.get_entity(entity_id)
      assert entity.archetype == :spawnable_player
    end
    
    test "spawns entity with custom options" do
      opts = %{
        metadata: %{level: 10},
        tags: [:veteran],
        parent_id: nil
      }
      
      {:ok, entity_id} = EntityArchetype.spawn_entity(:spawnable_player, opts)
      
      {:ok, entity} = EntityRegistry.get_entity(entity_id)
      assert entity.metadata.level == 10
      assert :veteran in entity.tags
    end
    
    test "spawns multiple entities efficiently" do
      {:ok, entity_ids} = EntityArchetype.spawn_entities(:spawnable_player, 5)
      
      assert length(entity_ids) == 5
      
      # Verify all entities were created
      Enum.each(entity_ids, fn entity_id ->
        {:ok, entity} = EntityRegistry.get_entity(entity_id)
        assert entity.archetype == :spawnable_player
      end)
    end
    
    test "spawns entity with variation" do
      opts = %{variation: :veteran}
      
      {:ok, entity_id} = EntityArchetype.spawn_entity(:player, opts)
      
      # Should have veteran variation applied
      {:ok, entity} = EntityRegistry.get_entity(entity_id)
      assert entity.archetype == :player
    end
    
    test "spawns entity with component overrides" do
      opts = %{
        component_overrides: %{
          health: %{current: 200, max: 200}
        }
      }
      
      {:ok, entity_id} = EntityArchetype.spawn_entity(:player, opts)
      
      # Verify override was applied
      {:ok, health_component} = Storage.get_component(entity_id, :health)
      assert health_component.current == 200
      assert health_component.max == 200
    end
  end
  
  describe "archetype inheritance" do
    test "creates archetype with inheritance" do
      # Create base archetype
      base_archetype = create_test_archetype(:base_unit)
      EntityArchetype.register_archetype(base_archetype)
      
      # Create derived archetype
      derived_archetype = %{
        name: :derived_unit,
        description: "Derived unit",
        components: [
          %{
            component_name: :special_ability,
            default_data: %{ability: "fireball"},
            required: true,
            variations: %{}
          }
        ],
        parent: :base_unit,
        spawn_config: %{},
        variations: %{},
        metadata: %{}
      }
      
      EntityArchetype.register_archetype(derived_archetype)
      
      # Get complete components (should include inherited)
      {:ok, complete_components} = EntityArchetype.get_complete_components(:derived_unit)
      
      component_names = Enum.map(complete_components, & &1.component_name)
      assert :position in component_names  # From base
      assert :health in component_names    # From base
      assert :special_ability in component_names  # From derived
    end
    
    test "prevents circular inheritance" do
      arch1 = %{
        name: :circular1,
        description: "Circular 1",
        components: [],
        parent: :circular2,
        spawn_config: %{},
        variations: %{},
        metadata: %{}
      }
      
      arch2 = %{
        name: :circular2,
        description: "Circular 2", 
        components: [],
        parent: :circular1,
        spawn_config: %{},
        variations: %{},
        metadata: %{}
      }
      
      EntityArchetype.register_archetype(arch1)
      
      # Should fail due to circular reference
      {:error, _reason} = EntityArchetype.register_archetype(arch2)
    end
  end
  
  describe "archetype variations" do
    test "creates archetype variation" do
      archetype_def = create_test_archetype(:variable_unit)
      EntityArchetype.register_archetype(archetype_def)
      
      variation_data = %{
        description: "Elite version",
        component_overrides: %{
          health: %{current: 200, max: 200}
        }
      }
      
      :ok = EntityArchetype.create_variation(:variable_unit, :elite, variation_data)
      
      {:ok, archetype} = EntityArchetype.get_archetype(:variable_unit)
      assert Map.has_key?(archetype.variations, :elite)
    end
  end
  
  describe "archetype statistics" do
    setup do
      archetype_def = create_test_archetype(:stats_archetype)
      EntityArchetype.register_archetype(archetype_def)
      :ok
    end
    
    test "tracks spawn statistics" do
      initial_stats = EntityArchetype.get_archetype_stats(:stats_archetype)
      assert initial_stats.spawn_count == 0
      
      EntityArchetype.spawn_entity(:stats_archetype)
      
      updated_stats = EntityArchetype.get_archetype_stats(:stats_archetype)
      assert updated_stats.spawn_count == 1
      assert updated_stats.last_spawned != nil
    end
    
    test "gets comprehensive statistics" do
      EntityArchetype.spawn_entities(:stats_archetype, 3)
      
      all_stats = EntityArchetype.get_all_stats()
      
      assert Map.has_key?(all_stats, :stats_archetype)
      assert all_stats.stats_archetype.spawn_count == 3
    end
  end
  
  describe "validation" do
    test "validates valid archetype definition" do
      archetype_def = create_test_archetype(:valid_archetype)
      
      :ok = EntityArchetype.validate_archetype(archetype_def)
    end
    
    test "rejects archetype with missing required fields" do
      invalid_archetype = %{
        description: "Missing name and components"
      }
      
      {:error, {:missing_fields, missing}} = EntityArchetype.validate_archetype(invalid_archetype)
      assert :name in missing
      assert :components in missing
    end
    
    test "rejects archetype with invalid components" do
      invalid_archetype = %{
        name: :invalid_comp,
        components: [
          %{
            # Missing component_name and default_data
            required: true
          }
        ]
      }
      
      {:error, {:invalid_components, _invalid}} = EntityArchetype.validate_archetype(invalid_archetype)
    end
  end
  
  describe "built-in archetypes" do
    test "has built-in player archetype" do
      {:ok, player_archetype} = EntityArchetype.get_archetype(:player)
      
      assert player_archetype.name == :player
      assert length(player_archetype.components) > 0
      
      component_names = Enum.map(player_archetype.components, & &1.component_name)
      assert :position in component_names
      assert :health in component_names
      assert :inventory in component_names
    end
    
    test "has built-in npc archetype" do
      {:ok, npc_archetype} = EntityArchetype.get_archetype(:npc)
      
      assert npc_archetype.name == :npc
      
      component_names = Enum.map(npc_archetype.components, & &1.component_name)
      assert :position in component_names
      assert :health in component_names
      assert :ai_controller in component_names
    end
    
    test "spawns built-in archetypes successfully" do
      {:ok, player_id} = EntityArchetype.spawn_entity(:player)
      {:ok, npc_id} = EntityArchetype.spawn_entity(:npc)
      {:ok, item_id} = EntityArchetype.spawn_entity(:item)
      
      {:ok, player} = EntityRegistry.get_entity(player_id)
      {:ok, npc} = EntityRegistry.get_entity(npc_id)
      {:ok, item} = EntityRegistry.get_entity(item_id)
      
      assert player.archetype == :player
      assert npc.archetype == :npc
      assert item.archetype == :item
    end
  end
  
  # Helper functions
  
  defp create_test_archetype(name) do
    %{
      name: name,
      description: "Test archetype for #{name}",
      components: [
        %{
          component_name: :position,
          default_data: %{x: 0.0, y: 0.0, z: 0.0},
          required: true,
          variations: %{
            center: %{x: 50.0, y: 50.0, z: 0.0}
          }
        },
        %{
          component_name: :health,
          default_data: %{current: 100, max: 100},
          required: true,
          variations: %{
            veteran: %{current: 150, max: 150}
          }
        }
      ],
      parent: nil,
      spawn_config: %{
        default_tags: [:test],
        auto_register: true
      },
      variations: %{
        veteran: %{default_tags: [:test, :veteran]}
      },
      metadata: %{
        category: :test,
        description: "Test archetype"
      }
    }
  end
end