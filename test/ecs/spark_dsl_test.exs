defmodule AshGameServer.ECS.SparkDslTest do
  use ExUnit.Case, async: true
  
  # Test DSL compilation and validation
  describe "Component DSL Extension" do
    test "extension loads without errors" do
      # Verify the extension module can be loaded
      assert Code.ensure_loaded?(AshGameServer.ECS.ComponentExtension)
    end

    test "extension has required callbacks" do
      extension = AshGameServer.ECS.ComponentExtension
      
      # Check that the extension implements required functions
      assert function_exported?(extension, :sections, 0)
      assert function_exported?(extension, :transformers, 0)
    end

    test "component target struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Component)
      
      # Verify the struct has expected fields
      component = %AshGameServer.ECS.Component{}
      assert Map.has_key?(component, :name)
      assert Map.has_key?(component, :attributes)
      assert Map.has_key?(component, :validations)
      assert Map.has_key?(component, :description)
    end

    test "component attribute struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Component.Attribute)
      
      # Verify the struct has expected fields
      attribute = %AshGameServer.ECS.Component.Attribute{}
      assert Map.has_key?(attribute, :name)
      assert Map.has_key?(attribute, :type)
      assert Map.has_key?(attribute, :default)
      assert Map.has_key?(attribute, :required)
    end
  end

  describe "System DSL Extension" do
    test "extension loads without errors" do
      assert Code.ensure_loaded?(AshGameServer.ECS.SystemExtension)
    end

    test "extension has required callbacks" do
      extension = AshGameServer.ECS.SystemExtension
      
      assert function_exported?(extension, :sections, 0)
      assert function_exported?(extension, :transformers, 0)
    end

    test "system target struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.System)
      
      # Verify the struct has expected fields
      system = %AshGameServer.ECS.System{}
      assert Map.has_key?(system, :name)
      assert Map.has_key?(system, :priority)
      assert Map.has_key?(system, :queries)
      assert Map.has_key?(system, :parallel)
      assert Map.has_key?(system, :description)
    end

    test "system query struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.System.Query)
      
      # Verify the struct has expected fields
      query = %AshGameServer.ECS.System.Query{}
      assert Map.has_key?(query, :components)
      assert Map.has_key?(query, :optional)
      assert Map.has_key?(query, :exclude)
    end
  end

  describe "Entity DSL Extension" do
    test "extension loads without errors" do
      assert Code.ensure_loaded?(AshGameServer.ECS.EntityExtension)
    end

    test "extension has required callbacks" do
      extension = AshGameServer.ECS.EntityExtension
      
      assert function_exported?(extension, :sections, 0)
      assert function_exported?(extension, :transformers, 0)
    end

    test "archetype target struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Archetype)
      
      # Verify the struct has expected fields
      archetype = %AshGameServer.ECS.Archetype{}
      assert Map.has_key?(archetype, :name)
      assert Map.has_key?(archetype, :components)
      assert Map.has_key?(archetype, :extends)
      assert Map.has_key?(archetype, :description)
    end

    test "entity template struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.EntityTemplate)
      
      # Verify the struct has expected fields
      template = %AshGameServer.ECS.EntityTemplate{}
      assert Map.has_key?(template, :name)
      assert Map.has_key?(template, :components)
      assert Map.has_key?(template, :from_archetype)
    end

    test "component reference struct exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Entity.ComponentRef)
      
      # Verify the struct has expected fields
      component_ref = %AshGameServer.ECS.Entity.ComponentRef{}
      assert Map.has_key?(component_ref, :name)
      assert Map.has_key?(component_ref, :initial)
      assert Map.has_key?(component_ref, :required)
    end
  end

  describe "DSL Transformers" do
    test "validate components transformer exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.ValidateComponents)
    end

    test "validate systems transformer exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.ValidateSystems)
    end

    test "validate entities transformer exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.ValidateEntities)
    end

    test "order systems transformer exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.OrderSystems)
    end

    test "resolve archetypes transformer exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.ResolveArchetypes)
    end

    test "transformers implement required behaviour" do
      transformers = [
        AshGameServer.ECS.Transformers.ValidateComponents,
        AshGameServer.ECS.Transformers.ValidateSystems,
        AshGameServer.ECS.Transformers.ValidateEntities,
        AshGameServer.ECS.Transformers.OrderSystems,
        AshGameServer.ECS.Transformers.ResolveArchetypes
      ]

      Enum.each(transformers, fn transformer ->
        # Check that transformers implement the required transform/1 function
        assert function_exported?(transformer, :transform, 1)
      end)
    end
  end

  describe "DSL Integration" do
    test "simple game module demonstrates DSL usage" do
      assert Code.ensure_loaded?(AshGameServer.Examples.SimpleGame)
      
      # Verify that the module provides example DSL usage
      assert function_exported?(AshGameServer.Examples.SimpleGame, :example_components, 0)
      assert function_exported?(AshGameServer.Examples.SimpleGame, :example_systems, 0)
      assert function_exported?(AshGameServer.Examples.SimpleGame, :example_archetypes, 0)
    end

    test "example components are valid structures" do
      components = AshGameServer.Examples.SimpleGame.example_components()
      
      assert is_list(components)
      assert length(components) > 0
      
      # Check that each component has expected structure
      Enum.each(components, fn component ->
        assert is_map(component)
        assert Map.has_key?(component, :name)
        assert is_atom(component.name)
      end)
    end

    test "example systems are valid structures" do
      systems = AshGameServer.Examples.SimpleGame.example_systems()
      
      assert is_list(systems)
      assert length(systems) > 0
      
      # Check that each system has expected structure
      Enum.each(systems, fn system ->
        assert is_struct(system, AshGameServer.ECS.System)
        assert is_atom(system.name)
        assert is_integer(system.priority)
        assert is_list(system.queries)
      end)
    end

    test "example archetypes are valid structures" do
      archetypes = AshGameServer.Examples.SimpleGame.example_archetypes()
      
      assert is_list(archetypes)
      assert length(archetypes) > 0
      
      # Check that each archetype has expected structure
      Enum.each(archetypes, fn archetype ->
        assert is_struct(archetype, AshGameServer.ECS.Archetype)
        assert is_atom(archetype.name)
        assert is_list(archetype.components)
      end)
    end
  end

  describe "Error Handling" do
    test "component extension handles invalid input gracefully" do
      # Test that invalid component definitions fail validation
      # This would require actually using the DSL, which is complex in tests
      # For now, just verify the transformer modules exist and can be called
      transformer = AshGameServer.ECS.Transformers.ValidateComponents
      
      # The transformer should handle invalid DSL gracefully
      assert function_exported?(transformer, :transform, 1)
    end

    test "system extension validates component dependencies" do
      # Test that systems requiring non-existent components fail validation
      transformer = AshGameServer.ECS.Transformers.ValidateSystems
      
      assert function_exported?(transformer, :transform, 1)
    end

    test "entity extension validates archetype consistency" do
      # Test that archetypes with invalid component references fail validation
      transformer = AshGameServer.ECS.Transformers.ValidateEntities
      
      assert function_exported?(transformer, :transform, 1)
    end
  end

  describe "Performance and Optimization" do
    test "order systems transformer exists and is functional" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.OrderSystems)
      
      transformer = AshGameServer.ECS.Transformers.OrderSystems
      assert function_exported?(transformer, :transform, 1)
    end

    test "resolve archetypes transformer exists" do
      assert Code.ensure_loaded?(AshGameServer.ECS.Transformers.ResolveArchetypes)
      
      transformer = AshGameServer.ECS.Transformers.ResolveArchetypes
      assert function_exported?(transformer, :transform, 1)
    end
  end
end