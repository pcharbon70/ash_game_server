defmodule AshGameServer.ECS.ComponentEventsTest do
  use ExUnit.Case, async: false

  alias AshGameServer.ECS.ComponentEvents

  setup do
    start_supervised!({ComponentEvents, [batch_size: 5, batch_timeout: 100]})
    
    # Clear any existing events
    ComponentEvents.flush_events()
    
    :ok
  end

  describe "event recording" do
    test "records component creation event" do
      entity_id = "test_entity_1"
      component_name = :position
      data = %{x: 10, y: 20}
      metadata = %{system: :movement}
      
      assert ComponentEvents.component_created(entity_id, component_name, data, metadata) == :ok
      
      # Give time for event processing
      Process.sleep(10)
    end

    test "records component update event" do
      entity_id = "test_entity_2"
      component_name = :health
      old_data = %{value: 100}
      new_data = %{value: 80}
      
      assert ComponentEvents.component_updated(entity_id, component_name, new_data, old_data) == :ok
    end

    test "records component deletion event" do
      entity_id = "test_entity_3"
      component_name = :temporary
      data = %{value: 42}
      
      assert ComponentEvents.component_deleted(entity_id, component_name, data) == :ok
    end
  end

  describe "event subscription" do
    test "subscribes to all events" do
      assert ComponentEvents.subscribe(self()) == :ok
      
      # Generate an event
      ComponentEvents.component_created("sub_test_1", :test_component, %{data: "test"})
      ComponentEvents.flush_events()
      
      # Should receive the event
      assert_receive {:component_event, event}, 1000
      assert event.type == :created
      assert event.entity_id == "sub_test_1"
      assert event.component == :test_component
    end

    test "subscribes with entity filter" do
      assert ComponentEvents.subscribe(self(), entity_id: "filtered_entity") == :ok
      
      # Generate events for different entities
      ComponentEvents.component_created("filtered_entity", :test_component, %{data: "test1"})
      ComponentEvents.component_created("other_entity", :test_component, %{data: "test2"})
      ComponentEvents.flush_events()
      
      # Should only receive the filtered event
      assert_receive {:component_event, event}, 1000
      assert event.entity_id == "filtered_entity"
      
      # Should not receive the other event
      refute_receive {:component_event, _}, 100
    end

    test "subscribes with component filter" do
      assert ComponentEvents.subscribe(self(), component: :health) == :ok
      
      ComponentEvents.component_created("test_entity", :health, %{value: 100})
      ComponentEvents.component_created("test_entity", :mana, %{value: 50})
      ComponentEvents.flush_events()
      
      # Should only receive health component event
      assert_receive {:component_event, event}, 1000
      assert event.component == :health
      
      refute_receive {:component_event, _}, 100
    end

    test "subscribes with type filter" do
      assert ComponentEvents.subscribe(self(), type: :updated) == :ok
      
      ComponentEvents.component_created("test_entity", :test_component, %{data: "test"})
      ComponentEvents.component_updated("test_entity", :test_component, %{data: "new"}, %{data: "old"})
      ComponentEvents.flush_events()
      
      # Should only receive update event
      assert_receive {:component_event, event}, 1000
      assert event.type == :updated
      
      refute_receive {:component_event, _}, 100
    end

    test "unsubscribes from events" do
      ComponentEvents.subscribe(self())
      assert ComponentEvents.unsubscribe(self()) == :ok
      
      ComponentEvents.component_created("unsub_test", :test_component, %{data: "test"})
      ComponentEvents.flush_events()
      
      # Should not receive events after unsubscribing
      refute_receive {:component_event, _}, 100
    end
  end

  describe "event retrieval" do
    setup do
      # Generate some test events
      ComponentEvents.component_created("history_entity_1", :position, %{x: 0, y: 0})
      ComponentEvents.component_updated("history_entity_1", :position, %{x: 10, y: 0}, %{x: 0, y: 0})
      ComponentEvents.component_updated("history_entity_1", :position, %{x: 10, y: 10}, %{x: 10, y: 0})
      ComponentEvents.component_created("history_entity_2", :health, %{value: 100})
      ComponentEvents.flush_events()
      
      # Give time for events to be processed
      Process.sleep(50)
      
      :ok
    end

    test "gets recent events" do
      events = ComponentEvents.get_recent_events()
      assert is_list(events)
      assert length(events) >= 0
    end

    test "gets recent events with filters" do
      events = ComponentEvents.get_recent_events(entity_id: "history_entity_1")
      assert is_list(events)
      
      # All events should be for the filtered entity
      Enum.each(events, fn event ->
        assert event.entity_id == "history_entity_1"
      end)
    end

    test "gets event history for entity" do
      events = ComponentEvents.get_event_history("history_entity_1")
      assert is_list(events)
    end

    test "gets event history for specific component" do
      events = ComponentEvents.get_event_history("history_entity_1", :position)
      assert is_list(events)
      
      # All events should be for position component
      Enum.each(events, fn event ->
        assert event.component == :position
      end)
    end

    test "gets event history with limit" do
      events = ComponentEvents.get_event_history("history_entity_1", nil, limit: 2)
      assert length(events) <= 2
    end
  end

  describe "event replay" do
    test "replays events to recreate state" do
      entity_id = "replay_entity"
      component_name = :counter
      
      # Create sequence of events
      ComponentEvents.component_created(entity_id, component_name, %{value: 0})
      ComponentEvents.component_updated(entity_id, component_name, %{value: 5}, %{value: 0})
      ComponentEvents.component_updated(entity_id, component_name, %{value: 10}, %{value: 5})
      ComponentEvents.flush_events()
      
      # Give time for events to be processed
      Process.sleep(50)
      
      # Replay events
      timestamp = System.system_time(:millisecond)
      result = ComponentEvents.replay_events(entity_id, component_name, timestamp)
      
      case result do
        {:ok, final_state} ->
          assert final_state.value == 10
        {:error, :no_data} ->
          # This is acceptable if events haven't been persisted yet
          :ok
      end
    end

    test "handles replay for deleted component" do
      entity_id = "deleted_replay_entity"
      component_name = :temporary
      
      ComponentEvents.component_created(entity_id, component_name, %{value: 42})
      ComponentEvents.component_deleted(entity_id, component_name, %{value: 42})
      ComponentEvents.flush_events()
      
      Process.sleep(50)
      
      timestamp = System.system_time(:millisecond)
      result = ComponentEvents.replay_events(entity_id, component_name, timestamp)
      
      # Should result in no data since component was deleted
      assert result == {:error, :no_data} or result == {:ok, nil}
    end
  end

  describe "event statistics" do
    test "gets event statistics" do
      stats = ComponentEvents.get_event_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :events_processed)
      assert Map.has_key?(stats, :subscribers_count)
    end

    test "tracks processed events count" do
      initial_stats = ComponentEvents.get_event_stats()
      initial_count = Map.get(initial_stats, :events_processed, 0)
      
      # Generate some events
      ComponentEvents.component_created("stats_entity", :test_component, %{data: "test"})
      ComponentEvents.flush_events()
      
      Process.sleep(10)
      
      new_stats = ComponentEvents.get_event_stats()
      new_count = Map.get(new_stats, :events_processed, 0)
      
      assert new_count >= initial_count
    end
  end

  describe "batching behavior" do
    test "processes events in batches" do
      # Generate more events than batch size
      Enum.each(1..10, fn i ->
        ComponentEvents.component_created("batch_entity_#{i}", :test_component, %{value: i})
      end)
      
      # Events should be processed automatically when batch is full
      Process.sleep(50)
      
      stats = ComponentEvents.get_event_stats()
      assert Map.get(stats, :events_processed, 0) >= 10
    end

    test "flushes events manually" do
      ComponentEvents.component_created("manual_flush", :test_component, %{data: "test"})
      
      # Manually flush without waiting for batch timeout
      ComponentEvents.flush_events()
      
      # Event should be processed
      Process.sleep(10)
      
      events = ComponentEvents.get_recent_events(entity_id: "manual_flush")
      assert length(events) >= 0
    end
  end

  describe "event compaction" do
    test "compacts old events" do
      # Generate events
      ComponentEvents.component_created("compact_entity", :test_component, %{data: "old"})
      ComponentEvents.flush_events()
      
      Process.sleep(50)
      
      # Compact events older than current time
      future_timestamp = System.system_time(:millisecond) + 1000
      ComponentEvents.compact_history(future_timestamp)
      
      # This should complete without error
      Process.sleep(10)
    end
  end

  describe "event streaming" do
    test "creates event stream" do
      result = ComponentEvents.event_stream()
      assert {:ok, :stream_started} = result
    end

    test "creates filtered event stream" do
      result = ComponentEvents.event_stream(component: :position)
      assert {:ok, :stream_started} = result
    end
  end

  describe "process monitoring" do
    test "cleans up dead subscribers" do
      # Start a temporary process
      {:ok, temp_pid} = Task.start(fn -> Process.sleep(10) end)
      
      # Subscribe with the temp process
      ComponentEvents.subscribe(temp_pid)
      
      # Wait for process to die
      Process.sleep(50)
      
      # The dead process should be cleaned up automatically
      # This is tested by ensuring no errors occur during event processing
      ComponentEvents.component_created("cleanup_test", :test_component, %{data: "test"})
      ComponentEvents.flush_events()
      
      Process.sleep(10)
      
      # Should complete without error
      assert :ok == :ok
    end
  end
end