defmodule AshGameServer.Storage.ComponentStorageTest do
  use ExUnit.Case, async: false  # Run tests sequentially to avoid table conflicts
  alias AshGameServer.Storage.ComponentStorage
  alias AshGameServer.Examples.SimpleGame

  setup do
    # Initialize components for testing (only once)
    component_definitions = SimpleGame.example_components()
    ComponentStorage.initialize_components(component_definitions)
    
    # Clean up any existing test data
    for entity_id <- 1..1000 do
      ComponentStorage.delete_component(entity_id, :position)
      ComponentStorage.delete_component(entity_id, :velocity)
      ComponentStorage.delete_component(entity_id, :health)
      ComponentStorage.delete_component(entity_id, :inventory)
    end
    
    :ok
  end

  describe "component operations" do
    test "put and get component" do
      entity_id = 1
      component_name = :position
      component_data = %{x: 10.0, y: 20.0, z: 0.0}
      
      # Put component
      assert :ok = ComponentStorage.put_component(entity_id, component_name, component_data)
      
      # Get component
      assert {:ok, ^component_data} = ComponentStorage.get_component(entity_id, component_name)
    end

    test "get non-existent component returns error" do
      entity_id = 999
      component_name = :position
      
      assert {:error, :not_found} = ComponentStorage.get_component(entity_id, component_name)
    end

    test "has_component? works correctly" do
      entity_id = 1
      component_name = :health
      component_data = %{current: 100, max: 100}
      
      # Initially should not have component
      assert false = ComponentStorage.has_component?(entity_id, component_name)
      
      # Add component
      ComponentStorage.put_component(entity_id, component_name, component_data)
      
      # Now should have component
      assert true = ComponentStorage.has_component?(entity_id, component_name)
    end

    test "delete component" do
      entity_id = 1
      component_name = :velocity
      component_data = %{dx: 1.0, dy: 0.0, dz: 0.0}
      
      # Add component
      ComponentStorage.put_component(entity_id, component_name, component_data)
      assert {:ok, ^component_data} = ComponentStorage.get_component(entity_id, component_name)
      
      # Delete component
      assert :ok = ComponentStorage.delete_component(entity_id, component_name)
      
      # Should no longer exist
      assert {:error, :not_found} = ComponentStorage.get_component(entity_id, component_name)
      assert false = ComponentStorage.has_component?(entity_id, component_name)
    end

    test "put_components with multiple components" do
      entity_id = 1
      components = %{
        position: %{x: 5.0, y: 10.0, z: 0.0},
        velocity: %{dx: 2.0, dy: 1.0, dz: 0.0},
        health: %{current: 80, max: 100}
      }
      
      # Put multiple components
      assert :ok = ComponentStorage.put_components(entity_id, components)
      
      # Verify each component
      Enum.each(components, fn {name, data} ->
        assert {:ok, ^data} = ComponentStorage.get_component(entity_id, name)
      end)
    end

    test "get_components retrieves multiple components" do
      entity_id = 1
      components = %{
        position: %{x: 15.0, y: 25.0, z: 5.0},
        health: %{current: 90, max: 100}
      }
      
      # Put components
      ComponentStorage.put_components(entity_id, components)
      
      # Get multiple components
      result = ComponentStorage.get_components(entity_id, [:position, :health, :inventory])
      
      # Should return existing components and skip missing ones
      assert %{position: %{x: 15.0, y: 25.0, z: 5.0}, health: %{current: 90, max: 100}} = result
      refute Map.has_key?(result, :inventory)
    end
  end

  describe "batch operations" do
    test "query entities with required components" do
      # Create test entities with different component sets
      ComponentStorage.put_components(1, %{position: %{x: 1, y: 1}, velocity: %{dx: 1, dy: 0}})
      ComponentStorage.put_components(2, %{position: %{x: 2, y: 2}, health: %{current: 100}})
      ComponentStorage.put_components(3, %{position: %{x: 3, y: 3}, velocity: %{dx: 0, dy: 1}, health: %{current: 80}})
      ComponentStorage.put_components(4, %{inventory: %{items: []}})
      
      # Query entities with position component
      position_entities = ComponentStorage.get_entities_with_component(:position)
      assert 1 in position_entities
      assert 2 in position_entities
      assert 3 in position_entities
      refute 4 in position_entities
      
      # Query entities with multiple components
      moving_entities = ComponentStorage.get_entities_with_components([:position, :velocity])
      assert 1 in moving_entities
      assert 3 in moving_entities
      refute 2 in moving_entities
      refute 4 in moving_entities
    end
  end

  describe "statistics and monitoring" do
    test "component statistics are tracked" do
      entity_id = 1
      component_name = :position
      component_data = %{x: 10.0, y: 20.0, z: 0.0}
      
      # Put component (should increment stats)
      ComponentStorage.put_component(entity_id, component_name, component_data)
      
      # Get stats
      {:ok, stats} = ComponentStorage.component_stats(component_name)
      
      assert stats.size >= 1
      assert stats.memory > 0
    end

    test "all component statistics" do
      # Add components to different entities
      ComponentStorage.put_component(1, :position, %{x: 10.0, y: 20.0, z: 0.0})
      ComponentStorage.put_component(2, :health, %{current: 100, max: 100})
      ComponentStorage.put_component(3, :velocity, %{dx: 1.0, dy: 0.0, dz: 0.0})
      
      # Get all stats
      all_stats = ComponentStorage.all_component_stats()
      
      assert is_list(all_stats)
      assert length(all_stats) >= 3
      
      # Check that stats contain expected information
      Enum.each(all_stats, fn stat ->
        assert Map.has_key?(stat, :name)
        assert Map.has_key?(stat, :size)
        assert Map.has_key?(stat, :memory)
      end)
    end
  end

  describe "performance optimization" do
    test "optimize storage" do
      # Add and delete some components to create optimization opportunities
      entity_id = 1
      ComponentStorage.put_component(entity_id, :position, %{x: 10.0, y: 20.0, z: 0.0})
      ComponentStorage.delete_component(entity_id, :position)
      
      # Optimize storage
      result = ComponentStorage.optimize_storage()
      
      # Should return optimization results
      assert is_map(result)
      assert Map.has_key?(result, :optimized_tables)
    end

    test "field updates work correctly" do
      entity_id = 1
      component_name = :position
      initial_data = %{x: 10.0, y: 20.0, z: 0.0}
      
      # Put initial component
      ComponentStorage.put_component(entity_id, component_name, initial_data)
      
      # Update specific fields
      field_updates = %{x: 25.0, z: 5.0}
      assert :ok = ComponentStorage.update_component_field(entity_id, component_name, field_updates)
      
      # Check updated data
      {:ok, updated_data} = ComponentStorage.get_component(entity_id, component_name)
      assert updated_data.x == 25.0
      assert updated_data.y == 20.0  # Should remain unchanged
      assert updated_data.z == 5.0
    end
  end
end