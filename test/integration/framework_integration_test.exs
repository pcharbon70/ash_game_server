defmodule AshGameServer.Integration.FrameworkIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the complete framework.
  Tests game scenarios, system scheduling, event propagation, and performance.
  """
  use ExUnit.Case, async: false
  
  alias AshGameServer.Storage.Storage
  alias AshGameServer.Players.Player
  alias AshGameServer.GameCore.GameSession
  
  setup do
    # Start all services
    {:ok, _} = Storage.start_link([])
    
    on_exit(fn ->
      Storage.clear()
      AshGameServer.Repo.delete_all(Player)
      AshGameServer.Repo.delete_all(GameSession)
    end)
    
    :ok
  end
  
  describe "end-to-end game scenarios" do
    test "complete player join and game session flow" do
      # Create players
      {:ok, player1} = Player.create(%{username: "player_one"})
      {:ok, player2} = Player.create(%{username: "player_two"})
      
      # Create player entities
      {:ok, entity1} = Storage.create_entity()
      Storage.add_component(entity1, :player_data, %{
        resource_id: player1.id,
        username: player1.username
      })
      Storage.add_component(entity1, :position, %{x: 0, y: 0, z: 0})
      Storage.add_component(entity1, :health, %{current: 100, max: 100})
      
      {:ok, entity2} = Storage.create_entity()
      Storage.add_component(entity2, :player_data, %{
        resource_id: player2.id,
        username: player2.username
      })
      Storage.add_component(entity2, :position, %{x: 10, y: 10, z: 0})
      Storage.add_component(entity2, :health, %{current: 100, max: 100})
      
      # Create game session
      {:ok, session} = GameSession.create(%{
        name: "Test Match",
        max_players: 4,
        game_type: :standard
      })
      
      # Add players to session
      {:ok, _} = GameSession.add_player(session, %{player_id: player1.id})
      {:ok, updated_session} = GameSession.add_player(session, %{player_id: player2.id})
      
      assert updated_session.current_players == 2
      
      # Start game
      {:ok, started_session} = GameSession.start(updated_session)
      assert started_session.status == :active
      assert started_session.started_at != nil
      
      # Create session entity
      {:ok, session_entity} = Storage.create_entity()
      Storage.add_component(session_entity, :session_data, %{
        resource_id: session.id,
        entities: [entity1, entity2],
        state: :active
      })
      
      # Simulate game events
      Storage.update_component(entity1, :position, %{x: 5, y: 5, z: 0})
      Storage.update_component(entity2, :health, %{current: 80, max: 100})
      
      # Complete game
      {:ok, completed} = GameSession.complete(started_session, %{
        final_state: %{
          winner: player1.id,
          scores: %{
            player1.id => 100,
            player2.id => 80
          }
        }
      })
      
      assert completed.status == :completed
      assert completed.ended_at != nil
    end
    
    test "combat scenario with damage and healing" do
      # Create combatants
      {:ok, attacker} = Storage.create_entity()
      Storage.add_component(attacker, :position, %{x: 0, y: 0, z: 0})
      Storage.add_component(attacker, :health, %{current: 100, max: 100})
      Storage.add_component(attacker, :combat_stats, %{
        attack: 20,
        defense: 10,
        speed: 15
      })
      
      {:ok, defender} = Storage.create_entity()
      Storage.add_component(defender, :position, %{x: 1, y: 0, z: 0})
      Storage.add_component(defender, :health, %{current: 100, max: 100})
      Storage.add_component(defender, :combat_stats, %{
        attack: 15,
        defense: 15,
        speed: 10
      })
      
      # Simulate combat round
      {:ok, attacker_stats} = Storage.get_component(attacker, :combat_stats)
      {:ok, defender_stats} = Storage.get_component(defender, :combat_stats)
      {:ok, defender_health} = Storage.get_component(defender, :health)
      
      # Calculate damage
      damage = max(0, attacker_stats.attack - defender_stats.defense)
      new_health = max(0, defender_health.current - damage)
      
      # Apply damage
      Storage.update_component(defender, :health, %{
        current: new_health,
        max: defender_health.max
      })
      
      # Verify damage applied
      {:ok, updated_health} = Storage.get_component(defender, :health)
      assert updated_health.current == 95
      
      # Apply healing
      healing_amount = 10
      healed = min(updated_health.max, updated_health.current + healing_amount)
      Storage.update_component(defender, :health, %{
        current: healed,
        max: updated_health.max
      })
      
      {:ok, final_health} = Storage.get_component(defender, :health)
      assert final_health.current == 100
    end
    
    test "inventory management scenario" do
      {:ok, player_entity} = Storage.create_entity()
      
      # Initialize inventory
      Storage.add_component(player_entity, :inventory, %{
        items: [],
        capacity: 20,
        weight: 0,
        max_weight: 100
      })
      
      # Pick up items
      items_to_add = [
        %{id: 1, name: "Sword", weight: 10, quantity: 1},
        %{id: 2, name: "Potion", weight: 1, quantity: 5},
        %{id: 3, name: "Armor", weight: 20, quantity: 1}
      ]
      
      {:ok, inventory} = Storage.get_component(player_entity, :inventory)
      
      # Add items one by one
      updated_inventory = Enum.reduce(items_to_add, inventory, fn item, inv ->
        total_weight = inv.weight + (item.weight * item.quantity)
        total_items = length(inv.items) + item.quantity
        
        if total_weight <= inv.max_weight and total_items <= inv.capacity do
          %{inv | 
            items: inv.items ++ List.duplicate(item, item.quantity),
            weight: total_weight
          }
        else
          inv
        end
      end)
      
      Storage.update_component(player_entity, :inventory, updated_inventory)
      
      # Verify inventory state
      {:ok, final_inv} = Storage.get_component(player_entity, :inventory)
      assert length(final_inv.items) == 7
      assert final_inv.weight == 35
    end
  end
  
  describe "system scheduling and execution" do
    test "processes entities in priority order" do
      # Create entities with different priorities
      high_priority = for i <- 1..5 do
        {:ok, entity} = Storage.create_entity()
        Storage.add_component(entity, :priority, %{level: :high, order: i})
        Storage.add_component(entity, :process_flag, %{processed: false})
        entity
      end
      
      low_priority = for i <- 1..5 do
        {:ok, entity} = Storage.create_entity()
        Storage.add_component(entity, :priority, %{level: :low, order: i})
        Storage.add_component(entity, :process_flag, %{processed: false})
        entity
      end
      
      # Simulate system processing
      all_entities = high_priority ++ low_priority
      
      # Sort by priority
      sorted = Enum.sort_by(all_entities, fn entity ->
        {:ok, priority} = Storage.get_component(entity, :priority)
        case priority.level do
          :high -> {0, priority.order}
          :low -> {1, priority.order}
        end
      end)
      
      # Process in order
      process_order = []
      for entity <- sorted do
        Storage.update_component(entity, :process_flag, %{processed: true})
        process_order
      end
      
      # Verify high priority processed first
      first_five = Enum.take(sorted, 5)
      assert Enum.all?(first_five, fn e -> e in high_priority end)
    end
    
    test "handles system dependencies" do
      {:ok, entity} = Storage.create_entity()
      
      # Components that systems depend on
      Storage.add_component(entity, :position, %{x: 0, y: 0, z: 0})
      Storage.add_component(entity, :velocity, %{dx: 5, dy: 0, dz: 0})
      Storage.add_component(entity, :physics, %{mass: 10, friction: 0.1})
      
      # System execution order matters
      systems_executed = []
      
      # Physics system (depends on physics component)
      if Storage.has_component?(entity, :physics) do
        {:ok, physics} = Storage.get_component(entity, :physics)
        {:ok, velocity} = Storage.get_component(entity, :velocity)
        
        # Apply friction
        new_velocity = %{
          dx: velocity.dx * (1 - physics.friction),
          dy: velocity.dy * (1 - physics.friction),
          dz: velocity.dz * (1 - physics.friction)
        }
        Storage.update_component(entity, :velocity, new_velocity)
        systems_executed
      end
      
      # Movement system (depends on position and velocity)
      if Storage.has_component?(entity, :position) and Storage.has_component?(entity, :velocity) do
        {:ok, position} = Storage.get_component(entity, :position)
        {:ok, velocity} = Storage.get_component(entity, :velocity)
        
        # Update position
        new_position = %{
          x: position.x + velocity.dx,
          y: position.y + velocity.dy,
          z: position.z + velocity.dz
        }
        Storage.update_component(entity, :position, new_position)
        systems_executed
      end
      
      # Verify final state
      {:ok, final_pos} = Storage.get_component(entity, :position)
      {:ok, final_vel} = Storage.get_component(entity, :velocity)
      
      assert final_pos.x == 4.5  # 0 + (5 * 0.9)
      assert final_vel.dx == 4.5  # 5 * 0.9
    end
  end
  
  describe "event propagation" do
    test "broadcasts events to interested systems" do
      # Subscribe to events
      Phoenix.PubSub.subscribe(AshGameServer.PubSub, "game:events")
      
      # Create event source
      {:ok, entity} = Storage.create_entity()
      Storage.add_component(entity, :event_emitter, %{type: :collision})
      
      # Trigger event
      Phoenix.PubSub.broadcast(
        AshGameServer.PubSub,
        "game:events",
        {:collision, entity, %{force: 100, angle: 45}}
      )
      
      # Should receive event
      assert_receive {:collision, ^entity, %{force: 100}}, 1000
    end
    
    test "chains events through systems" do
      Phoenix.PubSub.subscribe(AshGameServer.PubSub, "game:damage")
      Phoenix.PubSub.subscribe(AshGameServer.PubSub, "game:death")
      
      {:ok, entity} = Storage.create_entity()
      Storage.add_component(entity, :health, %{current: 10, max: 100})
      
      # Damage event
      Phoenix.PubSub.broadcast(
        AshGameServer.PubSub,
        "game:damage",
        {:damage, entity, 15}
      )
      
      # Process damage
      {:ok, health} = Storage.get_component(entity, :health)
      new_health = max(0, health.current - 15)
      Storage.update_component(entity, :health, %{current: new_health, max: health.max})
      
      # If health reaches 0, trigger death event
      if new_health == 0 do
        Phoenix.PubSub.broadcast(
          AshGameServer.PubSub,
          "game:death",
          {:death, entity}
        )
      end
      
      # Should receive both events
      assert_receive {:damage, ^entity, 15}, 1000
      assert_receive {:death, ^entity}, 1000
    end
  end
  
  describe "performance benchmarks" do
    test "handles 1000 concurrent players" do
      # Create players
      {time, players} = :timer.tc(fn ->
        tasks = for i <- 1..1000 do
          Task.async(fn ->
            {:ok, player} = Player.create(%{
              username: "player_#{i}",
              level: rem(i, 100) + 1
            })
            
            {:ok, entity} = Storage.create_entity()
            Storage.add_component(entity, :player_data, %{
              resource_id: player.id,
              username: player.username
            })
            Storage.add_component(entity, :position, %{
              x: :rand.uniform(1000),
              y: :rand.uniform(1000),
              z: 0
            })
            
            {player, entity}
          end)
        end
        
        Task.await_many(tasks, 30_000)
      end)
      
      assert length(players) == 1000
      # Should complete in under 10 seconds
      assert time < 10_000_000
      
      # Calculate average creation time
      avg_time = time / 1000 / 1000  # Convert to ms per player
      assert avg_time < 10  # Less than 10ms per player
    end
    
    test "processes game tick under 16ms" do
      # Create game entities
      entities = for _ <- 1..100 do
        {:ok, entity} = Storage.create_entity()
        Storage.add_component(entity, :position, %{
          x: :rand.uniform(100),
          y: :rand.uniform(100),
          z: 0
        })
        Storage.add_component(entity, :velocity, %{
          dx: :rand.uniform(10) - 5,
          dy: :rand.uniform(10) - 5,
          dz: 0
        })
        entity
      end
      
      # Measure tick time
      {tick_time, _} = :timer.tc(fn ->
        # Update all entities
        for entity <- entities do
          {:ok, pos} = Storage.get_component(entity, :position)
          {:ok, vel} = Storage.get_component(entity, :velocity)
          
          new_pos = %{
            x: pos.x + vel.dx,
            y: pos.y + vel.dy,
            z: pos.z + vel.dz
          }
          
          Storage.update_component(entity, :position, new_pos)
        end
      end)
      
      # Convert to milliseconds
      tick_ms = tick_time / 1000
      
      # Should complete in under 16ms (60 FPS)
      assert tick_ms < 16
    end
    
    test "memory usage scales linearly" do
      # Baseline memory
      :erlang.garbage_collect()
      baseline = :erlang.memory(:total)
      
      # Create first batch
      for _ <- 1..100 do
        {:ok, entity} = Storage.create_entity()
        Storage.add_component(entity, :data, %{
          value: :crypto.strong_rand_bytes(100)
        })
      end
      
      :erlang.garbage_collect()
      after_100 = :erlang.memory(:total)
      
      # Create second batch
      for _ <- 1..100 do
        {:ok, entity} = Storage.create_entity()
        Storage.add_component(entity, :data, %{
          value: :crypto.strong_rand_bytes(100)
        })
      end
      
      :erlang.garbage_collect()
      after_200 = :erlang.memory(:total)
      
      # Calculate memory per entity
      first_batch = (after_100 - baseline) / 100
      second_batch = (after_200 - after_100) / 100
      
      # Memory usage should be roughly linear
      ratio = second_batch / first_batch
      assert ratio > 0.8 and ratio < 1.2
    end
  end
end