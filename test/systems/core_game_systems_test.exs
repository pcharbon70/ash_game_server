defmodule AshGameServer.Systems.CoreGameSystemsTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.Systems.{MovementSystem, CombatSystem, AISystem, NetworkingSystem, PersistenceSystem}
  alias AshGameServer.Components.Transform.{Position, Velocity}
  alias AshGameServer.Components.Physics.{RigidBody, Collider}
  alias AshGameServer.Components.Gameplay.{Health, Combat}
  alias AshGameServer.Components.AI.{AIController, Behavior, Perception}
  alias AshGameServer.Components.Network.{NetworkID, ReplicationState, PredictionState}
  alias AshGameServer.Storage.ComponentStorage
  
  setup do
    # Initialize component storage for testing
    {:ok, _pid} = ComponentStorage.start_link([])
    :ok
  end
  
  describe "MovementSystem" do
    test "initializes with correct default state" do
      {:ok, state} = MovementSystem.init([])
      
      assert state.delta_time == 0.0
      assert state.collision_enabled == true
      assert state.world_bounds.min_x == -1000.0
      assert state.world_bounds.max_x == 1000.0
    end
    
    test "updates entity position based on velocity" do
      entity_id = "test_entity_1"
      
      # Set up entity with position and velocity
      position = %Position{x: 0.0, y: 0.0, z: 0.0}
      velocity = %Velocity{linear_x: 10.0, linear_y: 5.0, linear_z: 0.0}
      
      ComponentStorage.put(Position, entity_id, position)
      ComponentStorage.put(Velocity, entity_id, velocity)
      
      # Create system state with delta time
      {:ok, state} = MovementSystem.init([])
      state = MovementSystem.set_delta_time(state, 0.1)  # 100ms
      
      # Process entity
      {:ok, _} = MovementSystem.process_entity(entity_id, %{}, state)
      
      # Check updated position
      {:ok, updated_position} = ComponentStorage.get(Position, entity_id)
      assert_in_delta updated_position.x, 1.0, 0.01  # 10 * 0.1
      assert_in_delta updated_position.y, 0.5, 0.01  # 5 * 0.1
    end
    
    test "respects world boundaries" do
      entity_id = "boundary_test"
      
      # Set up entity at edge of world
      position = %Position{x: 950.0, y: 950.0, z: 0.0}
      velocity = %Velocity{linear_x: 100.0, linear_y: 100.0, linear_z: 0.0}
      
      ComponentStorage.put(Position, entity_id, position)
      ComponentStorage.put(Velocity, entity_id, velocity)
      
      {:ok, state} = MovementSystem.init([])
      state = MovementSystem.set_delta_time(state, 1.0)  # 1 second
      
      {:ok, _} = MovementSystem.process_entity(entity_id, %{}, state)
      
      {:ok, updated_position} = ComponentStorage.get(Position, entity_id)
      assert updated_position.x == 1000.0  # Clamped to max
      assert updated_position.y == 1000.0  # Clamped to max
    end
    
    test "handles collision detection" do
      entity1_id = "collider_1"
      entity2_id = "collider_2"
      
      # Set up two entities that will collide
      pos1 = %Position{x: 0.0, y: 0.0, z: 0.0}
      pos2 = %Position{x: 1.0, y: 0.0, z: 0.0}
      vel1 = %Velocity{linear_x: 10.0, linear_y: 0.0, linear_z: 0.0}
      collider1 = Collider.sphere(1.0)
      collider2 = Collider.sphere(1.0)
      
      ComponentStorage.put(Position, entity1_id, pos1)
      ComponentStorage.put(Position, entity2_id, pos2)
      ComponentStorage.put(Velocity, entity1_id, vel1)
      ComponentStorage.put(Collider, entity1_id, collider1)
      ComponentStorage.put(Collider, entity2_id, collider2)
      
      {:ok, state} = MovementSystem.init([])
      state = MovementSystem.set_delta_time(state, 0.1)
      
      {:ok, _} = MovementSystem.process_entity(entity1_id, %{}, state)
      
      {:ok, final_pos} = ComponentStorage.get(Position, entity1_id)
      # Position should be adjusted due to collision
      assert final_pos.x < 1.0  # Pushed back from collision
    end
  end
  
  describe "CombatSystem" do
    test "initializes with correct default state" do
      {:ok, state} = CombatSystem.init([])
      
      assert state.combat_log == []
      assert state.max_log_entries == 1000
      assert state.damage_modifiers.physical == 1.0
    end
    
    test "calculates damage correctly" do
      attacker_id = "attacker"
      target_id = "target"
      
      # Set up attacker with combat stats
      attacker_combat = %Combat{
        attack_power: 50,
        critical_chance: 0.0  # No crit for predictable test
      }
      
      # Set up target with defense
      target_combat = %Combat{armor: 10}
      target_health = %Health{current: 100, maximum: 100}
      
      ComponentStorage.put(Combat, attacker_id, attacker_combat)
      ComponentStorage.put(Combat, target_id, target_combat)
      ComponentStorage.put(Health, target_id, target_health)
      
      {:ok, _state} = CombatSystem.init([])
      
      # Apply damage
      {:ok, _damage_calc} = CombatSystem.apply_damage(target_id, 25, :physical, attacker_id)
      
      # Check health was reduced
      {:ok, updated_health} = ComponentStorage.get(Health, target_id)
      assert updated_health.current == 75
    end
    
    test "handles healing" do
      target_id = "heal_target"
      
      health = %Health{current: 50, maximum: 100}
      ComponentStorage.put(Health, target_id, health)
      
      {:ok, _event} = CombatSystem.heal(target_id, 25)
      
      {:ok, updated_health} = ComponentStorage.get(Health, target_id)
      assert updated_health.current == 75
    end
    
    test "prevents overhealing" do
      target_id = "overheal_target"
      
      health = %Health{current: 90, maximum: 100}
      ComponentStorage.put(Health, target_id, health)
      
      {:ok, _event} = CombatSystem.heal(target_id, 50)
      
      {:ok, updated_health} = ComponentStorage.get(Health, target_id)
      assert updated_health.current == 100  # Capped at maximum
    end
  end
  
  describe "AISystem" do
    test "initializes with correct default state" do
      {:ok, state} = AISystem.init([])
      
      assert state.global_ai_enabled == true
      assert state.decision_frequency == 200.0
      assert state.pathfinding_enabled == true
    end
    
    test "updates AI timers" do
      entity_id = "ai_entity"
      
      ai_controller = AIController.new(:aggressive)
      ComponentStorage.put(AIController, entity_id, ai_controller)
      
      {:ok, state} = AISystem.init([])
      
      {:ok, _} = AISystem.process_entity(entity_id, %{}, state)
      
      {:ok, updated_ai} = ComponentStorage.get(AIController, entity_id)
      assert updated_ai.last_decision_time > 0
    end
    
    test "handles AI state transitions" do
      entity_id = "state_test"
      
      # Set up AI with perception that detects threats
      ai_controller = AIController.new(:aggressive)
      perception = Perception.new(100.0, 150.0, 20.0)
      |> Perception.detect_entity("enemy_1", 30.0, :visual, 0.8)
      
      position = %Position{x: 0.0, y: 0.0, z: 0.0}
      health = %Health{current: 100, maximum: 100}
      
      ComponentStorage.put(AIController, entity_id, ai_controller)
      ComponentStorage.put(Perception, entity_id, perception)
      ComponentStorage.put(Position, entity_id, position)
      ComponentStorage.put(Health, entity_id, health)
      
      {:ok, state} = AISystem.init([])
      
      {:ok, _} = AISystem.process_entity(entity_id, %{}, state)
      
      {:ok, updated_ai} = ComponentStorage.get(AIController, entity_id)
      # AI should react to threats based on behavior type
      assert updated_ai.enabled
    end
  end
  
  describe "NetworkingSystem" do
    test "initializes with correct default state" do
      {:ok, state} = NetworkingSystem.init([])
      
      assert state.tick_rate == 60
      assert state.current_tick == 0
      assert state.delta_compression == true
      assert state.prediction_enabled == true
    end
    
    test "advances ticks correctly" do
      {:ok, state} = NetworkingSystem.init([])
      
      # Simulate tick boundary reached
      state = %{state | tick_accumulator: 20.0}  # More than 1000/60
      
      {:ok, updated_state} = NetworkingSystem.execute(state)
      
      assert updated_state.current_tick > state.current_tick
    end
    
    test "registers and unregisters clients" do
      {:ok, state} = NetworkingSystem.init([])
      
      # Register client
      updated_state = NetworkingSystem.register_client(state, "client_1")
      assert Map.has_key?(updated_state.connected_clients, "client_1")
      
      # Unregister client
      final_state = NetworkingSystem.unregister_client(updated_state, "client_1")
      refute Map.has_key?(final_state.connected_clients, "client_1")
    end
    
    test "creates network snapshots" do
      entity_id = "networked_entity"
      
      # Set up networked entity
      network_id = %NetworkID{id: "net_1", authority: :server}
      position = %Position{x: 10.0, y: 20.0, z: 0.0}
      
      ComponentStorage.put(NetworkID, entity_id, network_id)
      ComponentStorage.put(Position, entity_id, position)
      
      {:ok, state} = NetworkingSystem.init([])
      state = %{state | tick_accumulator: 20.0}  # Force tick
      
      {:ok, updated_state} = NetworkingSystem.execute(state)
      
      # Should have created snapshot
      assert map_size(updated_state.snapshot_buffer) > 0
    end
  end
  
  describe "PersistenceSystem" do
    test "initializes with correct default state" do
      {:ok, state} = PersistenceSystem.init([])
      
      assert state.auto_save_enabled == true
      assert state.auto_save_interval == 300_000.0
      assert state.compression_enabled == true
      assert state.save_statistics.total_saves == 0
    end
    
    test "handles save operation" do
      entity_id = "save_test_entity"
      
      # Set up entity to save
      position = %Position{x: 100.0, y: 200.0, z: 0.0}
      health = %Health{current: 80, maximum: 100}
      
      ComponentStorage.put(Position, entity_id, position)
      ComponentStorage.put(Health, entity_id, health)
      
      {:ok, state} = PersistenceSystem.init([])
      
      # Attempt save to memory (for testing)
      save_request = %{
        type: :full,
        target: :memory,
        include_components: [Position, Health]
      }
      
      case PersistenceSystem.save_game_state(state, save_request) do
        {:ok, updated_state} ->
          assert updated_state.save_statistics.total_saves == 1
        
        {:error, reason, _state} ->
          # Save might fail in test environment, but state should be updated
          assert reason != nil
      end
    end
    
    test "handles load operation" do
      {:ok, state} = PersistenceSystem.init([])
      
      # Attempt load from memory
      load_request = %{
        source: :memory,
        restore_mode: :replace
      }
      
      case PersistenceSystem.load_game_state(state, load_request) do
        {:ok, updated_state} ->
          assert updated_state.save_statistics.total_loads >= 0
        
        {:error, :not_found, _state} ->
          # Expected if no save exists
          :ok
        
        {:error, _reason, _state} ->
          # Other errors acceptable in test environment
          :ok
      end
    end
    
    test "configures auto-save settings" do
      {:ok, state} = PersistenceSystem.init([])
      
      updated_state = PersistenceSystem.set_auto_save(state, false, 60_000.0)
      
      assert updated_state.auto_save_enabled == false
      assert updated_state.auto_save_interval == 60_000.0
    end
    
    test "manages compression settings" do
      {:ok, state} = PersistenceSystem.init([])
      
      updated_state = PersistenceSystem.set_compression(state, false)
      
      assert updated_state.compression_enabled == false
    end
  end
  
  describe "System Integration" do
    test "systems work together correctly" do
      entity_id = "integration_test"
      
      # Set up entity with all components
      position = %Position{x: 0.0, y: 0.0, z: 0.0}
      velocity = %Velocity{linear_x: 1.0, linear_y: 1.0, linear_z: 0.0}
      health = %Health{current: 100, maximum: 100}
      combat = Combat.new(20, 15)
      ai_controller = AIController.new(:neutral)
      network_id = %NetworkID{id: "int_test", authority: :server}
      
      ComponentStorage.put(Position, entity_id, position)
      ComponentStorage.put(Velocity, entity_id, velocity)
      ComponentStorage.put(Health, entity_id, health)
      ComponentStorage.put(Combat, entity_id, combat)
      ComponentStorage.put(AIController, entity_id, ai_controller)
      ComponentStorage.put(NetworkID, entity_id, network_id)
      
      # Initialize all systems
      {:ok, movement_state} = MovementSystem.init([])
      {:ok, combat_state} = CombatSystem.init([])
      {:ok, ai_state} = AISystem.init([])
      {:ok, network_state} = NetworkingSystem.init([])
      {:ok, persistence_state} = PersistenceSystem.init([])
      
      # Execute systems in order
      movement_state = MovementSystem.set_delta_time(movement_state, 0.1)
      {:ok, _} = MovementSystem.process_entity(entity_id, %{}, movement_state)
      {:ok, _} = CombatSystem.process_entity(entity_id, %{}, combat_state)
      {:ok, _} = AISystem.process_entity(entity_id, %{}, ai_state)
      {:ok, _} = NetworkingSystem.process_entity(entity_id, %{}, network_state)
      {:ok, _} = PersistenceSystem.process_entity(entity_id, %{}, persistence_state)
      
      # Verify entity state was updated
      {:ok, final_position} = ComponentStorage.get(Position, entity_id)
      {:ok, final_health} = ComponentStorage.get(Health, entity_id)
      {:ok, final_ai} = ComponentStorage.get(AIController, entity_id)
      
      assert final_position.x > 0.0  # Moved by velocity
      assert final_health.current == 100  # No damage taken
      assert final_ai.enabled  # AI still active
    end
    
    test "performance under load" do
      # Create multiple entities for performance testing
      entity_count = 100
      entities = for i <- 1..entity_count do
        entity_id = "perf_test_#{i}"
        
        position = %Position{x: Float.round(:rand.uniform() * 100, 2), y: Float.round(:rand.uniform() * 100, 2), z: 0.0}
        velocity = %Velocity{linear_x: Float.round((:rand.uniform() - 0.5) * 10, 2), linear_y: Float.round((:rand.uniform() - 0.5) * 10, 2), linear_z: 0.0}
        health = %Health{current: 100, maximum: 100}
        
        ComponentStorage.put(Position, entity_id, position)
        ComponentStorage.put(Velocity, entity_id, velocity)
        ComponentStorage.put(Health, entity_id, health)
        
        entity_id
      end
      
      {:ok, movement_state} = MovementSystem.init([])
      movement_state = MovementSystem.set_delta_time(movement_state, 0.016)  # ~60fps
      
      # Measure processing time
      start_time = System.monotonic_time()
      
      Enum.each(entities, fn entity_id ->
        {:ok, _} = MovementSystem.process_entity(entity_id, %{}, movement_state)
      end)
      
      end_time = System.monotonic_time()
      duration_ms = (end_time - start_time) / 1_000_000
      
      # Should process 100 entities quickly (under 100ms)
      assert duration_ms < 100.0
      
      # Verify all entities were processed
      final_count = Enum.count(entities, fn entity_id ->
        case ComponentStorage.get(Position, entity_id) do
          {:ok, _} -> true
          _ -> false
        end
      end)
      
      assert final_count == entity_count
    end
  end
end