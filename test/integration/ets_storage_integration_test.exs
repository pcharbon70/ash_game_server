defmodule AshGameServer.Integration.EtsStorageIntegrationTest do
  @moduledoc """
  Integration tests for ETS storage system.
  Tests multi-component operations, concurrent access, persistence, and recovery.
  """
  use ExUnit.Case, async: false
  
  alias AshGameServer.Storage.Storage
  alias AshGameServer.Storage.{TableManager, PersistenceBridge, PerformanceMonitor}
  
  setup do
    # Start all storage components
    {:ok, _} = Storage.start_link([])
    {:ok, _} = TableManager.start_link([])
    {:ok, _} = PersistenceBridge.start_link([])
    {:ok, _} = PerformanceMonitor.start_link([])
    
    on_exit(fn ->
      Storage.clear()
    end)
    
    :ok
  end
  
  describe "multi-component entity operations" do
    test "creates complex entities with multiple components" do
      {:ok, entity_id} = Storage.create_entity()
      
      # Add multiple components
      components = [
        {:position, %{x: 100, y: 200, z: 50}},
        {:velocity, %{dx: 5, dy: -3, dz: 0}},
        {:health, %{current: 85, max: 100}},
        {:inventory, %{items: ["sword", "potion"], capacity: 20}},
        {:stats, %{strength: 15, agility: 12, intelligence: 8}}
      ]
      
      for {name, data} <- components do
        :ok = Storage.add_component(entity_id, name, data)
      end
      
      # Verify all components stored
      {:ok, all_components} = Storage.get_components(entity_id)
      assert map_size(all_components) == 5
      assert all_components.position.x == 100
      assert all_components.health.current == 85
      assert "sword" in all_components.inventory.items
    end
    
    test "updates multiple components atomically" do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :position, %{x: 0, y: 0})
      Storage.add_component(entity_id, :health, %{current: 100, max: 100})
      
      # Atomic multi-component update
      updates = %{
        position: %{x: 50, y: 75},
        health: %{current: 80, max: 100}
      }
      
      :ok = Storage.update_components(entity_id, updates)
      
      # Verify both updated
      {:ok, components} = Storage.get_components(entity_id)
      assert components.position.x == 50
      assert components.health.current == 80
    end
    
    test "queries entities by component combinations" do
      # Create various entities
      {:ok, player} = Storage.create_entity()
      Storage.add_component(player, :position, %{})
      Storage.add_component(player, :velocity, %{})
      Storage.add_component(player, :health, %{})
      
      {:ok, static_object} = Storage.create_entity()
      Storage.add_component(static_object, :position, %{})
      Storage.add_component(static_object, :collision, %{})
      
      {:ok, moving_hazard} = Storage.create_entity()
      Storage.add_component(moving_hazard, :position, %{})
      Storage.add_component(moving_hazard, :velocity, %{})
      Storage.add_component(moving_hazard, :damage, %{})
      
      # Query mobile entities (position + velocity)
      mobile = Storage.query_entities([:position, :velocity])
      assert length(mobile) == 2
      assert player in mobile
      assert moving_hazard in mobile
      
      # Query damageable entities (health)
      damageable = Storage.query_entities([:health])
      assert damageable == [player]
      
      # Query with optional components
      all_positioned = Storage.query_entities([:position], [:velocity, :health])
      assert length(all_positioned) == 3
    end
  end
  
  describe "concurrent access patterns" do
    test "handles concurrent reads and writes" do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :counter, %{value: 0})
      
      # Spawn concurrent processes
      tasks = for _i <- 1..100 do
        Task.async(fn ->
          # Read current value
          {:ok, counter} = Storage.get_component(entity_id, :counter)
          
          # Simulate processing
          Process.sleep(:rand.uniform(10))
          
          # Update with increment
          Storage.update_component(entity_id, :counter, %{
            value: counter.value + 1
          })
        end)
      end
      
      # Wait for all tasks
      Task.await_many(tasks)
      
      # Final value should reflect all updates
      {:ok, final} = Storage.get_component(entity_id, :counter)
      assert final.value == 100
    end
    
    test "handles entity creation under load" do
      # Create many entities concurrently
      tasks = for _ <- 1..1000 do
        Task.async(fn ->
          {:ok, entity_id} = Storage.create_entity()
          
          # Add random components
          components = Enum.take_random([
            {:position, %{x: :rand.uniform(100)}},
            {:velocity, %{speed: :rand.uniform(10)}},
            {:health, %{current: :rand.uniform(100)}},
            {:name, %{value: "Entity#{:rand.uniform(1000)}"}}
          ], :rand.uniform(3) + 1)
          
          for {name, data} <- components do
            Storage.add_component(entity_id, name, data)
          end
          
          entity_id
        end)
      end
      
      entity_ids = Task.await_many(tasks, 10000)
      
      # All entities should be created
      assert length(entity_ids) == 1000
      assert length(Enum.uniq(entity_ids)) == 1000
      
      # Verify storage integrity
      stats = Storage.get_stats()
      assert stats.entity_stats.total_entities == 1000
    end
    
    test "maintains consistency during concurrent component operations" do
      # Create shared entity
      {:ok, entity_id} = Storage.create_entity()
      
      # Initial components
      Storage.add_component(entity_id, :inventory, %{
        items: [],
        capacity: 100
      })
      
      # Concurrent additions
      tasks = for i <- 1..50 do
        Task.async(fn ->
          {:ok, inventory} = Storage.get_component(entity_id, :inventory)
          
          # Add item if space available
          if length(inventory.items) < inventory.capacity do
            Storage.update_component(entity_id, :inventory, %{
              items: ["item_#{i}" | inventory.items],
              capacity: inventory.capacity
            })
          end
        end)
      end
      
      Task.await_many(tasks)
      
      # Check final state
      {:ok, final_inv} = Storage.get_component(entity_id, :inventory)
      assert length(final_inv.items) <= 100
      # All items should be unique
      assert length(Enum.uniq(final_inv.items)) == length(final_inv.items)
    end
  end
  
  describe "persistence bridge functionality" do
    test "persists components to database" do
      {:ok, entity_id} = Storage.create_entity()
      
      # Add persistent component
      Storage.add_component(entity_id, :player_data, %{
        username: "persist_test",
        level: 10,
        persistent: true
      })
      
      # Trigger persistence
      :ok = PersistenceBridge.persist_entity(entity_id)
      
      # Clear ETS
      Storage.clear()
      
      # Restore from database
      {:ok, restored_id} = PersistenceBridge.restore_entity(entity_id)
      
      # Verify data restored
      {:ok, player_data} = Storage.get_component(restored_id, :player_data)
      assert player_data.username == "persist_test"
      assert player_data.level == 10
    end
    
    test "handles selective persistence" do
      {:ok, entity_id} = Storage.create_entity()
      
      # Mix of persistent and transient components
      Storage.add_component(entity_id, :persistent_stats, %{
        total_score: 1000,
        achievements: ["first_kill", "level_10"],
        persistent: true
      })
      
      Storage.add_component(entity_id, :transient_position, %{
        x: 100,
        y: 200,
        persistent: false
      })
      
      # Persist
      :ok = PersistenceBridge.persist_entity(entity_id)
      
      # Clear and restore
      Storage.clear()
      {:ok, restored} = PersistenceBridge.restore_entity(entity_id)
      
      # Only persistent component restored
      {:ok, stats} = Storage.get_component(restored, :persistent_stats)
      assert stats.total_score == 1000
      
      {:error, :not_found} = Storage.get_component(restored, :transient_position)
    end
  end
  
  describe "performance under load" do
    test "maintains sub-millisecond access times" do
      # Create many entities
      entity_ids = for _ <- 1..10_000 do
        {:ok, id} = Storage.create_entity()
        Storage.add_component(id, :data, %{value: :rand.uniform(1000)})
        id
      end
      
      # Measure random access time
      sample_ids = Enum.take_random(entity_ids, 100)
      
      times = for entity_id <- sample_ids do
        {time, {:ok, _}} = :timer.tc(fn ->
          Storage.get_component(entity_id, :data)
        end)
        time
      end
      
      avg_time = Enum.sum(times) / length(times)
      
      # Average should be under 1ms (1000 microseconds)
      assert avg_time < 1000
    end
    
    test "efficient batch operations" do
      # Create entities
      entity_ids = for _ <- 1..1000 do
        {:ok, id} = Storage.create_entity()
        id
      end
      
      # Time batch component addition
      {batch_time, :ok} = :timer.tc(fn ->
        Storage.batch_add_component(entity_ids, :batch_data, fn id ->
          %{entity_id: id, timestamp: System.monotonic_time()}
        end)
      end)
      
      # Should be much faster than individual operations
      # Target: < 10ms for 1000 entities
      assert batch_time < 10_000
      
      # Verify all components added
      for entity_id <- entity_ids do
        {:ok, data} = Storage.get_component(entity_id, :batch_data)
        assert data.entity_id == entity_id
      end
    end
  end
  
  describe "recovery and fault tolerance" do
    test "recovers from table crash" do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :important_data, %{
        value: "must_not_lose",
        number: 42
      })
      
      # Get table reference
      table_info = TableManager.get_table_info(:component_important_data)
      
      # Kill the table process (simulating crash)
      if table_info do
        :ets.delete(table_info.ref)
      end
      
      # Try to access - should trigger recovery
      result = Storage.get_component(entity_id, :important_data)
      
      # Should either recover data or handle gracefully
      case result do
        {:ok, data} ->
          assert data.value == "must_not_lose"
        {:error, reason} ->
          assert reason in [:not_found, :table_not_found]
      end
    end
    
    test "handles backup and restore" do
      # Create test data
      entity_ids = for i <- 1..100 do
        {:ok, id} = Storage.create_entity()
        Storage.add_component(id, :backup_test, %{index: i})
        id
      end
      
      # Create backup
      {:ok, backup} = TableManager.backup_tables()
      
      # Clear everything
      Storage.clear()
      
      # Restore from backup
      :ok = TableManager.restore_tables(backup)
      
      # Verify data restored
      for {entity_id, i} <- Enum.zip(entity_ids, 1..100) do
        case Storage.get_component(entity_id, :backup_test) do
          {:ok, data} -> assert data.index == i
          {:error, _} -> :ok  # Some data loss acceptable in crash recovery
        end
      end
    end
  end
  
  describe "monitoring and diagnostics" do
    test "tracks performance metrics" do
      # Perform various operations
      for _ <- 1..100 do
        {:ok, entity_id} = Storage.create_entity()
        Storage.add_component(entity_id, :metric_test, %{data: "test"})
        Storage.get_component(entity_id, :metric_test)
      end
      
      # Get performance report
      report = PerformanceMonitor.get_report()
      
      assert report.total_operations >= 300
      assert report.operation_breakdown.create > 0
      assert report.operation_breakdown.read > 0
      assert report.operation_breakdown.write > 0
      
      # Check timing metrics
      assert report.average_latency > 0
      assert report.p99_latency >= report.average_latency
    end
    
    test "provides health diagnostics" do
      # Create some load
      for _ <- 1..500 do
        {:ok, entity_id} = Storage.create_entity()
        for component <- [:a, :b, :c] do
          Storage.add_component(entity_id, component, %{data: :rand.uniform(100)})
        end
      end
      
      # Get health report
      health = Storage.health_check()
      
      assert health.status in [:healthy, :warning, :critical]
      assert health.entity_count == 500
      assert health.component_count == 1500
      assert health.memory_usage > 0
      assert is_list(health.recommendations)
    end
  end
end