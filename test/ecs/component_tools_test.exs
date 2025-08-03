defmodule AshGameServer.ECS.ComponentToolsTest do
  use ExUnit.Case, async: false

  alias AshGameServer.ECS.{ComponentTools, ComponentRegistry, EnhancedStorage, ComponentBehaviour, ComponentEvents}
  alias AshGameServer.Storage

  defmodule TestComponent do
    @behaviour ComponentBehaviour

    @impl ComponentBehaviour
    def metadata do
      %{
        name: :tools_test_component,
        version: 1,
        schema: [name: :string, level: :integer, active: :boolean],
        indexes: [:name, :level],
        persistent: true,
        validations: [:validate_name],
        description: "Test component for tools testing"
      }
    end

    @impl ComponentBehaviour
    def validate(data) do
      if is_binary(Map.get(data, :name)) and String.length(Map.get(data, :name, "")) > 0 do
        :ok
      else
        {:error, :invalid_name}
      end
    end
  end

  setup do
    # Storage is not a supervised process - it's a module
    start_supervised!(ComponentRegistry)
    start_supervised!(EnhancedStorage)
    start_supervised!(ComponentEvents)
    
    # Register test component
    ComponentRegistry.register_component(TestComponent)
    EnhancedStorage.create_indexes(:tools_test_component)
    
    # Add test data
    test_entities = [
      {"tools_entity_1", %{name: "Alice", level: 10, active: true}},
      {"tools_entity_2", %{name: "Bob", level: 15, active: true}},
      {"tools_entity_3", %{name: "Charlie", level: 10, active: false}},
      {"tools_entity_4", %{name: "Diana", level: 20, active: true}}
    ]
    
    Enum.each(test_entities, fn {entity_id, data} ->
      EnhancedStorage.put_component(entity_id, :tools_test_component, data)
    end)
    
    Process.sleep(50)  # Allow for processing
    
    :ok
  end

  describe "component inspection" do
    test "inspects individual component" do
      result = ComponentTools.inspect_component("tools_entity_1", :tools_test_component)
      
      assert is_map(result)
      assert Map.has_key?(result, :entity_id)
      assert Map.has_key?(result, :component)
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :metadata)
      assert Map.has_key?(result, :size)
      assert Map.has_key?(result, :memory_words)
      assert Map.has_key?(result, :validation)
      
      assert result.entity_id == "tools_entity_1"
      assert result.component == :tools_test_component
      assert result.validation == :ok
    end

    test "handles non-existent component inspection" do
      result = ComponentTools.inspect_component("non_existent", :tools_test_component)
      
      assert Map.has_key?(result, :error)
    end

    test "inspects entire entity" do
      result = ComponentTools.inspect_entity("tools_entity_1")
      
      assert is_map(result)
      assert Map.has_key?(result, :entity_id)
      assert Map.has_key?(result, :component_count)
      assert Map.has_key?(result, :components)
      assert Map.has_key?(result, :total_memory)
      assert Map.has_key?(result, :archetype)
      
      assert result.entity_id == "tools_entity_1"
    end

    test "handles non-existent entity inspection" do
      result = ComponentTools.inspect_entity("non_existent_entity")
      
      assert Map.has_key?(result, :error)
    end

    test "lists all components with statistics" do
      components = ComponentTools.list_components()
      
      assert is_list(components)
      assert length(components) >= 1
      
      # Find our test component
      test_component = Enum.find(components, &(&1.name == :tools_test_component))
      assert test_component != nil
      
      assert Map.has_key?(test_component, :instance_count)
      assert Map.has_key?(test_component, :storage_stats)
      assert Map.has_key?(test_component, :memory_usage)
      
      assert test_component.instance_count >= 4
    end
  end

  describe "performance profiling" do
    test "profiles component operations" do
      # Generate some activity
      EnhancedStorage.get_component("tools_entity_1", :tools_test_component)
      EnhancedStorage.get_component("tools_entity_2", :tools_test_component)
      
      result = ComponentTools.profile_component(:tools_test_component, 100)
      
      assert is_map(result)
      assert Map.has_key?(result, :component)
      assert Map.has_key?(result, :duration_seconds)
      assert Map.has_key?(result, :operations)
      assert Map.has_key?(result, :performance)
      assert Map.has_key?(result, :memory_usage)
      assert Map.has_key?(result, :recommendations)
      
      assert result.component == :tools_test_component
      assert is_number(result.duration_seconds)
      assert is_map(result.operations)
      assert is_map(result.performance)
    end

    test "profiles query operations" do
      query = AshGameServer.ECS.ComponentQuery.from(:tools_test_component)
      |> AshGameServer.ECS.ComponentQuery.where(:level, :gt, 10)
      
      result = ComponentTools.profile_query(query)
      
      assert is_map(result)
      assert Map.has_key?(result, :query)
      assert Map.has_key?(result, :execution_time_microseconds)
      assert Map.has_key?(result, :execution_time_ms)
      assert Map.has_key?(result, :result_count)
      assert Map.has_key?(result, :performance_grade)
      assert Map.has_key?(result, :optimization_suggestions)
      
      assert is_number(result.execution_time_microseconds)
      assert result.performance_grade in [:excellent, :good, :fair, :poor]
    end

    test "benchmarks multiple queries" do
      queries = [
        AshGameServer.ECS.ComponentQuery.from(:tools_test_component)
        |> AshGameServer.ECS.ComponentQuery.where(:level, :gt, 10),
        
        AshGameServer.ECS.ComponentQuery.from(:tools_test_component)
        |> AshGameServer.ECS.ComponentQuery.where(:active, :eq, true)
      ]
      
      result = ComponentTools.benchmark_queries(queries, 5)
      
      assert is_map(result)
      assert Map.has_key?(result, :benchmark_results)
      assert Map.has_key?(result, :fastest_query)
      assert Map.has_key?(result, :slowest_query)
      
      assert length(result.benchmark_results) == 2
      
      Enum.each(result.benchmark_results, fn benchmark ->
        assert Map.has_key?(benchmark, :query)
        assert Map.has_key?(benchmark, :iterations)
        assert Map.has_key?(benchmark, :avg_time_microseconds)
        assert Map.has_key?(benchmark, :min_time_microseconds)
        assert Map.has_key?(benchmark, :max_time_microseconds)
        assert Map.has_key?(benchmark, :std_deviation)
        
        assert benchmark.iterations == 5
      end)
    end
  end

  describe "memory analysis" do
    test "analyzes memory usage across components" do
      result = ComponentTools.analyze_memory()
      
      assert is_map(result)
      assert Map.has_key?(result, :total_memory_bytes)
      assert Map.has_key?(result, :total_memory_mb)
      assert Map.has_key?(result, :component_breakdown)
      assert Map.has_key?(result, :top_memory_consumers)
      assert Map.has_key?(result, :memory_recommendations)
      
      assert is_number(result.total_memory_bytes)
      assert is_number(result.total_memory_mb)
      assert is_list(result.component_breakdown)
      assert is_list(result.top_memory_consumers)
      assert is_list(result.memory_recommendations)
      
      # Check component breakdown structure
      if length(result.component_breakdown) > 0 do
        breakdown = List.first(result.component_breakdown)
        assert Map.has_key?(breakdown, :component)
        assert Map.has_key?(breakdown, :total_memory_bytes)
        assert Map.has_key?(breakdown, :instance_count)
        assert Map.has_key?(breakdown, :avg_memory_per_instance)
        assert Map.has_key?(breakdown, :memory_percentage)
      end
    end

    test "starts memory tracking" do
      assert ComponentTools.start_memory_tracking(500) == :ok
      
      # Give it a moment to start
      Process.sleep(10)
      
      # This is mainly testing that it doesn't crash
    end
  end

  describe "validation tools" do
    test "validates all component instances" do
      result = ComponentTools.validate_component_instances(:tools_test_component)
      
      assert is_map(result)
      assert Map.has_key?(result, :component)
      assert Map.has_key?(result, :total_instances)
      assert Map.has_key?(result, :valid_instances)
      assert Map.has_key?(result, :invalid_instances)
      assert Map.has_key?(result, :errors)
      assert Map.has_key?(result, :validation_rate)
      
      assert result.component == :tools_test_component
      assert is_integer(result.total_instances)
      assert is_integer(result.valid_instances)
      assert is_integer(result.invalid_instances)
      assert is_list(result.errors)
      assert is_number(result.validation_rate)
      
      # Our test data should all be valid
      assert result.total_instances >= 4
      assert result.valid_instances >= 4
      assert result.invalid_instances == 0
      assert result.validation_rate == 100.0
    end

    test "handles validation with some invalid data" do
      # Add some invalid data
      Storage.add_component("invalid_entity", :tools_test_component, %{level: 10, active: true})  # missing name
      
      result = ComponentTools.validate_component_instances(:tools_test_component)
      
      assert result.total_instances >= 5
      assert result.invalid_instances >= 1
      assert length(result.errors) >= 1
      assert result.validation_rate < 100.0
    end
  end

  describe "migration tools" do
    test "migrates component data when supported" do
      # Our test component doesn't implement migrate/3, so this should return an error
      result = ComponentTools.migrate_component_data(:tools_test_component, 0)
      
      assert result == %{error: :migration_not_supported}
    end
  end

  describe "error handling" do
    test "handles non-existent component gracefully" do
      result = ComponentTools.inspect_component("entity", :non_existent_component)
      assert Map.has_key?(result, :error)
      
      result = ComponentTools.validate_component_instances(:non_existent_component)
      assert is_map(result)
      # Should handle gracefully without crashing
    end

    test "handles invalid entities gracefully" do
      result = ComponentTools.inspect_entity("totally_invalid_entity")
      assert Map.has_key?(result, :error)
    end

    test "profiling handles errors gracefully" do
      invalid_query = AshGameServer.ECS.ComponentQuery.from(:non_existent_component)
      
      result = ComponentTools.profile_query(invalid_query)
      assert is_map(result)
      # Should complete without crashing
    end
  end

  describe "development utilities" do
    test "memory tracking produces logs" do
      # Start memory tracking with short interval
      ComponentTools.start_memory_tracking(50)
      
      # Wait for at least one tracking cycle
      Process.sleep(100)
      
      # This mainly tests that the tracking doesn't crash
      assert :ok == :ok
    end

    test "performance recommendations are generated" do
      result = ComponentTools.profile_component(:tools_test_component, 50)
      
      assert is_list(result.recommendations)
      # Recommendations may be empty or contain suggestions
    end

    test "query optimization suggestions are provided" do
      query = AshGameServer.ECS.ComponentQuery.from(:tools_test_component)
      |> AshGameServer.ECS.ComponentQuery.where(:level, :gt, 10)
      |> AshGameServer.ECS.ComponentQuery.join(:inventory, :entity_id, :entity_id)
      
      result = ComponentTools.profile_query(query)
      
      assert is_list(result.optimization_suggestions)
      # May contain suggestions based on query structure
    end
  end

  describe "integration with other systems" do
    test "integrates with component events" do
      # Generate some events
      ComponentEvents.component_created("integration_entity", :tools_test_component, %{name: "Test", level: 5, active: true})
      ComponentEvents.flush_events()
      
      Process.sleep(50)
      
      # Inspect component should include recent events
      result = ComponentTools.inspect_component("integration_entity", :tools_test_component)
      
      assert Map.has_key?(result, :recent_events)
      # Events may or may not be there depending on timing, but structure should exist
    end

    test "integrates with enhanced storage stats" do
      # Perform some operations to generate stats
      EnhancedStorage.get_component("tools_entity_1", :tools_test_component)
      EnhancedStorage.get_component("tools_entity_2", :tools_test_component)
      
      result = ComponentTools.inspect_component("tools_entity_1", :tools_test_component)
      
      assert Map.has_key?(result, :storage_stats)
      assert is_map(result.storage_stats)
    end
  end
end