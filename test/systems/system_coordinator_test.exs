defmodule AshGameServer.Systems.SystemCoordinatorTest do
  use ExUnit.Case, async: false
  
  alias AshGameServer.Systems.SystemCoordinator
  
  setup do
    {:ok, pid} = SystemCoordinator.start_link()
    
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    {:ok, coordinator: pid}
  end
  
  describe "system registration" do
    test "registers system without dependencies" do
      assert :ok = SystemCoordinator.register_system(:test_system, [])
    end
    
    test "registers system with dependencies" do
      assert :ok = SystemCoordinator.register_system(:system_a, [])
      assert :ok = SystemCoordinator.register_system(:system_b, [:system_a])
    end
    
    test "detects dependency cycles" do
      assert :ok = SystemCoordinator.register_system(:system_a, [:system_b])
      assert {:error, :cycle_detected} = SystemCoordinator.register_system(:system_b, [:system_a])
    end
    
    test "unregisters system" do
      assert :ok = SystemCoordinator.register_system(:test_system, [])
      assert :ok = SystemCoordinator.unregister_system(:test_system)
    end
  end
  
  describe "shared state management" do
    test "stores and retrieves shared values" do
      assert :ok = SystemCoordinator.put_shared(:test_key, "test_value")
      assert {:ok, "test_value"} = SystemCoordinator.get_shared(:test_key)
    end
    
    test "returns error for non-existent key" do
      assert {:error, :not_found} = SystemCoordinator.get_shared(:non_existent)
    end
    
    test "updates shared value atomically" do
      assert :ok = SystemCoordinator.put_shared(:counter, 0)
      
      assert {:ok, 1} = SystemCoordinator.update_shared(:counter, &(&1 + 1))
      assert {:ok, 2} = SystemCoordinator.update_shared(:counter, &(&1 + 1))
      
      assert {:ok, 2} = SystemCoordinator.get_shared(:counter)
    end
    
    test "creates value if not exists during update" do
      assert {:ok, 10} = SystemCoordinator.update_shared(:new_key, fn nil -> 10 end)
      assert {:ok, 10} = SystemCoordinator.get_shared(:new_key)
    end
    
    test "deletes shared value" do
      assert :ok = SystemCoordinator.put_shared(:temp_key, "temp")
      assert :ok = SystemCoordinator.delete_shared(:temp_key)
      assert {:error, :not_found} = SystemCoordinator.get_shared(:temp_key)
    end
  end
  
  describe "event subscription" do
    test "subscribes to events" do
      assert :ok = SystemCoordinator.register_system(:listener, [])
      assert :ok = SystemCoordinator.subscribe(:listener, :test_event)
    end
    
    test "unsubscribes from events" do
      assert :ok = SystemCoordinator.register_system(:listener, [])
      assert :ok = SystemCoordinator.subscribe(:listener, :test_event)
      assert :ok = SystemCoordinator.unsubscribe(:listener, :test_event)
    end
    
    test "broadcasts events to subscribers" do
      # Register a test module that can receive events
      defmodule TestListener do
        def handle_event({:test_event, data}, _state) do
          send(:test_process, {:received_event, data})
          {:ok, %{}}
        end
      end
      
      Process.register(self(), :test_process)
      
      assert :ok = SystemCoordinator.register_system(TestListener, [])
      assert :ok = SystemCoordinator.subscribe(TestListener, :test_event)
      
      SystemCoordinator.broadcast_event(:test_event, %{message: "hello"})
      
      assert_receive {:received_event, %{message: "hello"}}, 1000
      
      Process.unregister(:test_process)
    end
  end
  
  describe "dependency checking" do
    test "checks if all dependencies are met" do
      assert :ok = SystemCoordinator.register_system(:base_system, [])
      assert :ok = SystemCoordinator.register_system(:dependent_system, [:base_system])
      
      assert {:ok, :all_met} = SystemCoordinator.check_dependencies(:dependent_system)
    end
    
    test "reports missing dependencies" do
      assert :ok = SystemCoordinator.register_system(:dependent_system, [:missing_system])
      
      assert {:error, {:missing_dependencies, [:missing_system]}} = 
        SystemCoordinator.check_dependencies(:dependent_system)
    end
    
    test "awaits system readiness" do
      assert :ok = SystemCoordinator.register_system(:dependent, [:required])
      
      # Start async wait
      task = Task.async(fn ->
        SystemCoordinator.await_ready(:dependent, 1000)
      end)
      
      # Register required system after a delay
      Process.sleep(200)
      assert :ok = SystemCoordinator.register_system(:required, [])
      
      # Task should complete successfully
      assert :ok = Task.await(task)
    end
  end
  
  describe "message passing" do
    test "sends messages between systems" do
      defmodule ReceiverSystem do
        def handle_event({:message, msg}, _state) do
          send(:test_process, {:received_message, msg})
          {:ok, %{}}
        end
      end
      
      Process.register(self(), :test_process)
      
      assert :ok = SystemCoordinator.register_system(:sender, [])
      assert :ok = SystemCoordinator.register_system(ReceiverSystem, [])
      
      SystemCoordinator.send_message(:sender, ReceiverSystem, "test message")
      
      assert_receive {:received_message, "test message"}, 1000
      
      Process.unregister(:test_process)
    end
  end
  
  describe "metrics" do
    test "collects coordinator metrics" do
      assert :ok = SystemCoordinator.register_system(:test_system, [])
      assert :ok = SystemCoordinator.put_shared(:test_key, "value")
      
      SystemCoordinator.broadcast_event(:test_event, %{})
      
      metrics = SystemCoordinator.get_metrics()
      
      assert metrics.registered_systems == 1
      assert metrics.shared_state_entries >= 1
      assert metrics.events_broadcast >= 1
    end
  end
end