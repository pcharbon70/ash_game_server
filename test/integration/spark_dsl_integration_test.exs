defmodule AshGameServer.Integration.SparkDslIntegrationTest do
  @moduledoc """
  Integration tests for Spark DSL compilation and runtime behavior.
  Tests DSL compilation, transformers, validation, and runtime execution.
  """
  use ExUnit.Case, async: false
  
  alias AshGameServer.Storage.Storage
  
  setup do
    {:ok, _} = Storage.start_link([])
    
    on_exit(fn ->
      Storage.clear()
    end)
    
    :ok
  end
  
  describe "DSL compilation and validation" do
    test "compiles complete game configuration" do
      defmodule TestGame do
        use AshGameServer.ECS.DSL
        
        components do
          component :position do
            attribute :x, :float, default: 0.0
            attribute :y, :float, default: 0.0
            attribute :z, :float, default: 0.0
          end
          
          component :velocity do
            attribute :dx, :float, default: 0.0
            attribute :dy, :float, default: 0.0
            attribute :dz, :float, default: 0.0
            attribute :max_speed, :float, default: 10.0
          end
          
          component :health do
            attribute :current, :integer, default: 100
            attribute :max, :integer, default: 100
            attribute :regeneration, :float, default: 0.0
          end
        end
        
        entities do
          archetype :player do
            with_component :position
            with_component :velocity
            with_component :health
          end
          
          archetype :enemy do
            extends :player
            with_component :ai_state
          end
        end
        
        systems do
          system :movement do
            requires [:position, :velocity]
            run_every 16
            priority :high
          end
          
          system :health_regen do
            requires [:health]
            run_every 1000
            priority :low
          end
        end
      end
      
      # Verify compilation succeeded
      assert Code.ensure_loaded?(TestGame)
      
      # Verify components accessible
      components = AshGameServer.ECS.ComponentExtension.get_components(TestGame)
      assert length(components) == 3
      
      # Verify archetypes
      archetypes = AshGameServer.ECS.EntityExtension.archetypes(TestGame)
      assert length(archetypes) == 2
      
      # Verify systems
      systems = AshGameServer.ECS.SystemExtension.get_systems(TestGame)
      assert length(systems) == 2
    end
    
    test "validates component definitions" do
      # Should fail with invalid type
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidComponent do
          use AshGameServer.ECS.DSL
          
          components do
            component :bad do
              attribute :value, :invalid_type
            end
          end
        end
      end
    end
    
    test "validates system requirements" do
      # Should fail with non-existent component requirement
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidSystem do
          use AshGameServer.ECS.DSL
          
          components do
            component :position do
              attribute :x, :float
            end
          end
          
          systems do
            system :broken do
              requires [:position, :non_existent]
            end
          end
        end
      end
    end
  end
  
  describe "transformer pipeline execution" do
    test "transformers modify DSL configuration" do
      defmodule TransformerTest do
        use AshGameServer.ECS.DSL
        
        components do
          component :indexed_component do
            attribute :id, :uuid
            attribute :name, :string
            indexed [:id, :name]
          end
        end
      end
      
      # Verify transformer added index configuration
      [component] = AshGameServer.ECS.ComponentExtension.get_components(TransformerTest)
      assert :id in component.indexed
      assert :name in component.indexed
    end
    
    test "archetype inheritance resolution" do
      defmodule InheritanceTest do
        use AshGameServer.ECS.DSL
        
        components do
          component :base do
            attribute :value, :integer
          end
          
          component :extended do
            attribute :extra, :string
          end
        end
        
        entities do
          archetype :parent do
            with_component :base
          end
          
          archetype :child do
            extends :parent
            with_component :extended
          end
        end
      end
      
      # Get resolved archetype
      child = AshGameServer.ECS.EntityExtension.get_archetype(InheritanceTest, :child)
      
      # Should have both components
      component_names = Enum.map(child.components, & &1.name)
      assert :base in component_names
      assert :extended in component_names
    end
  end
  
  describe "runtime behavior verification" do
    test "creates entities from archetypes at runtime" do
      defmodule RuntimeGame do
        use AshGameServer.ECS.DSL
        
        components do
          component :transform do
            attribute :position, :map
            attribute :rotation, :map
            attribute :scale, :map
          end
          
          component :physics do
            attribute :mass, :float
            attribute :velocity, :map
          end
        end
        
        entities do
          archetype :game_object do
            with_component :transform, initial: [
              position: %{x: 0, y: 0, z: 0},
              rotation: %{x: 0, y: 0, z: 0},
              scale: %{x: 1, y: 1, z: 1}
            ]
            with_component :physics, initial: [
              mass: 1.0,
              velocity: %{x: 0, y: 0, z: 0}
            ]
          end
        end
      end
      
      # Create entity from archetype
      archetype = AshGameServer.ECS.EntityExtension.get_archetype(RuntimeGame, :game_object)
      {:ok, entity_id} = Storage.create_entity()
      
      # Add components based on archetype
      for component_ref <- archetype.components do
        Storage.add_component(entity_id, component_ref.name, component_ref.initial)
      end
      
      # Verify entity has all components
      {:ok, transform} = Storage.get_component(entity_id, :transform)
      assert transform.position.x == 0
      assert transform.scale.x == 1
      
      {:ok, physics} = Storage.get_component(entity_id, :physics)
      assert physics.mass == 1.0
    end
    
    test "system execution with DSL configuration" do
      defmodule SystemExecutionGame do
        use AshGameServer.ECS.DSL
        
        components do
          component :counter do
            attribute :value, :integer, default: 0
          end
        end
        
        systems do
          system :increment do
            requires [:counter]
            run_every 100
          end
        end
      end
      
      # Create entities with counter
      entity_ids = for _ <- 1..5 do
        {:ok, id} = Storage.create_entity()
        Storage.add_component(id, :counter, %{value: 0})
        id
      end
      
      # Get system configuration
      [_system] = AshGameServer.ECS.SystemExtension.get_systems(SystemExecutionGame)
      
      # Simulate system execution
      for entity_id <- entity_ids do
        {:ok, counter} = Storage.get_component(entity_id, :counter)
        Storage.update_component(entity_id, :counter, %{value: counter.value + 1})
      end
      
      # Verify all entities updated
      for entity_id <- entity_ids do
        {:ok, counter} = Storage.get_component(entity_id, :counter)
        assert counter.value == 1
      end
    end
  end
  
  describe "error handling and reporting" do
    test "provides clear error messages for DSL mistakes" do
      error = try do
        defmodule ErrorReporting do
          use AshGameServer.ECS.DSL
          
          components do
            component :duplicate do
              attribute :value, :integer
            end
            
            component :duplicate do
              attribute :other, :string
            end
          end
        end
        nil
      rescue
        e in Spark.Error.DslError -> e
      end
      
      assert error
      assert error.message =~ "duplicate"
    end
    
    test "validates component attribute types at compile time" do
      error = try do
        defmodule TypeValidation do
          use AshGameServer.ECS.DSL
          
          components do
            component :typed do
              attribute :value, :integer, default: "not_an_integer"
            end
          end
        end
        nil
      rescue
        e in Spark.Error.DslError -> e
      end
      
      assert error
      assert error.message =~ "type"
    end
  end
  
  describe "DSL integration with storage" do
    test "component definitions drive storage table creation" do
      defmodule StorageIntegration do
        use AshGameServer.ECS.DSL
        
        components do
          component :persistent_data do
            attribute :id, :uuid
            attribute :value, :string
            persistent true
            table :custom_table
          end
        end
      end
      
      [component] = AshGameServer.ECS.ComponentExtension.get_components(StorageIntegration)
      
      # Component should specify custom table
      assert component.table == :custom_table
      assert component.persistent == true
      
      # Create entity with this component
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :persistent_data, %{
        id: Ecto.UUID.generate(),
        value: "test"
      })
      
      # Verify stored in correct table
      {:ok, data} = Storage.get_component(entity_id, :persistent_data)
      assert data.value == "test"
    end
  end
end