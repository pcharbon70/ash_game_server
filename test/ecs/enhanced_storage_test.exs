defmodule AshGameServer.ECS.EnhancedStorageTest do
  use ExUnit.Case, async: false

  alias AshGameServer.ECS.{EnhancedStorage, ComponentRegistry, ComponentBehaviour}
  alias AshGameServer.Storage

  defmodule TestComponent do
    @behaviour ComponentBehaviour

    @impl ComponentBehaviour
    def metadata do
      %{
        name: :enhanced_test_component,
        version: 1,
        schema: [name: :string, level: :integer, active: :boolean],
        indexes: [:name, :level],
        persistent: true,
        validations: [],
        description: "Test component for enhanced storage"
      }
    end

    @impl ComponentBehaviour
    def validate(data) do
      if is_map(data) and Map.has_key?(data, :name) do
        :ok
      else
        {:error, :invalid_data}
      end
    end
  end

  setup do
    # Storage is not a supervised process - it's a module
    start_supervised!(ComponentRegistry)
    start_supervised!(EnhancedStorage)
    
    # Register test component
    ComponentRegistry.register_component(TestComponent)
    EnhancedStorage.create_indexes(:enhanced_test_component)
    
    :ok
  end

  describe "component storage operations" do
    test "puts component with indexing" do
      entity_id = "test_entity_1"
      data = %{name: "Player1", level: 10, active: true}
      
      assert EnhancedStorage.put_component(entity_id, :enhanced_test_component, data) == :ok
      
      # Verify it's stored
      assert {:ok, ^data} = EnhancedStorage.get_component(entity_id, :enhanced_test_component)
    end

    test "updates component with index maintenance" do
      entity_id = "test_entity_2"
      initial_data = %{name: "Player2", level: 5, active: true}
      updated_data = %{name: "Player2", level: 15, active: false}
      
      EnhancedStorage.put_component(entity_id, :enhanced_test_component, initial_data)
      assert EnhancedStorage.update_component(entity_id, :enhanced_test_component, updated_data) == :ok
      
      assert {:ok, ^updated_data} = EnhancedStorage.get_component(entity_id, :enhanced_test_component)
    end

    test "removes component with index cleanup" do
      entity_id = "test_entity_3"
      data = %{name: "Player3", level: 20, active: true}
      
      EnhancedStorage.put_component(entity_id, :enhanced_test_component, data)
      assert EnhancedStorage.remove_component(entity_id, :enhanced_test_component) == :ok
      
      assert {:error, :not_found} = EnhancedStorage.get_component(entity_id, :enhanced_test_component)
    end

    test "rejects invalid component data" do
      entity_id = "test_entity_4"
      invalid_data = %{level: 10, active: true}  # missing name
      
      assert {:error, :invalid_data} = EnhancedStorage.put_component(entity_id, :enhanced_test_component, invalid_data)
    end
  end

  describe "index queries" do
    setup do
      # Add test data
      entities = [
        {"entity_1", %{name: "Alice", level: 10, active: true}},
        {"entity_2", %{name: "Bob", level: 15, active: true}},
        {"entity_3", %{name: "Charlie", level: 10, active: false}},
        {"entity_4", %{name: "Alice", level: 20, active: true}}
      ]
      
      Enum.each(entities, fn {entity_id, data} ->
        EnhancedStorage.put_component(entity_id, :enhanced_test_component, data)
      end)
      
      :ok
    end

    test "queries by name index" do
      alice_entities = EnhancedStorage.query_by_index(:enhanced_test_component, :name, "Alice")
      
      assert length(alice_entities) == 2
      assert "entity_1" in alice_entities
      assert "entity_4" in alice_entities
    end

    test "queries by level index" do
      level_10_entities = EnhancedStorage.query_by_index(:enhanced_test_component, :level, 10)
      
      assert length(level_10_entities) == 2
      assert "entity_1" in level_10_entities
      assert "entity_3" in level_10_entities
    end

    test "returns empty list for non-existent index value" do
      result = EnhancedStorage.query_by_index(:enhanced_test_component, :name, "NonExistent")
      assert result == []
    end
  end

  describe "batch operations" do
    test "batch get components efficiently" do
      entities = [
        {"batch_1", %{name: "Test1", level: 1, active: true}},
        {"batch_2", %{name: "Test2", level: 2, active: true}},
        {"batch_3", %{name: "Test3", level: 3, active: true}}
      ]
      
      # Store components
      Enum.each(entities, fn {entity_id, data} ->
        EnhancedStorage.put_component(entity_id, :enhanced_test_component, data)
      end)
      
      # Batch get
      requests = [
        {"batch_1", :enhanced_test_component},
        {"batch_2", :enhanced_test_component},
        {"batch_3", :enhanced_test_component}
      ]
      
      results = EnhancedStorage.batch_get_components(requests)
      
      assert length(results) == 3
      Enum.each(results, fn {_entity_id, _component_name, result} ->
        assert {:ok, _data} = result
      end)
    end
  end

  describe "storage statistics" do
    test "tracks component access statistics" do
      entity_id = "stats_entity"
      data = %{name: "StatsTest", level: 5, active: true}
      
      # Perform operations
      EnhancedStorage.put_component(entity_id, :enhanced_test_component, data)
      EnhancedStorage.get_component(entity_id, :enhanced_test_component)
      EnhancedStorage.get_component(entity_id, :enhanced_test_component)
      
      stats = EnhancedStorage.get_component_stats(:enhanced_test_component)
      
      assert stats.write_count >= 1
      assert stats.read_count >= 2
      assert is_number(stats.total_read_time)
      assert is_number(stats.total_write_time)
    end

    test "gets overall storage statistics" do
      stats = EnhancedStorage.get_storage_stats()
      assert is_map(stats)
    end
  end

  describe "storage optimization" do
    test "optimizes component storage" do
      # This is mainly testing that the function doesn't crash
      assert EnhancedStorage.optimize_component_storage(:enhanced_test_component) == :ok
    end

    test "creates indexes for component" do
      assert EnhancedStorage.create_indexes(:enhanced_test_component) == :ok
    end
  end

  describe "error handling" do
    test "handles non-existent component gracefully" do
      entity_id = "error_entity"
      
      assert {:error, _reason} = EnhancedStorage.get_component(entity_id, :non_existent_component)
    end

    test "handles storage errors gracefully" do
      entity_id = "error_entity_2"
      
      # Try to remove non-existent component
      assert EnhancedStorage.remove_component(entity_id, :enhanced_test_component) == :ok
    end
  end
end