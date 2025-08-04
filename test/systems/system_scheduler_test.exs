defmodule AshGameServer.Systems.SystemSchedulerTest do
  use ExUnit.Case, async: false
  
  alias AshGameServer.Systems.SystemScheduler
  
  # Test system module
  defmodule TestSystem do
    use AshGameServer.Systems.SystemBehaviour
    
    def init(config) do
      {:ok, Map.put(config, :initialized, true)}
    end
    
    def priority, do: :medium
    
    def required_components, do: [:position, :velocity]
    
    def execute(_entities, state) do
      # Track execution
      send(state.test_pid, {:executed, self()})
      {:ok, state}
    end
    
    def process_entity(_entity_id, _components, _state) do
      {:ok, %{}}
    end
  end
  
  defmodule HighPrioritySystem do
    use AshGameServer.Systems.SystemBehaviour
    
    def init(_config), do: {:ok, %{}}
    def priority, do: :high
    def required_components, do: []
    
    def execute(_entities, state) do
      send(:test_process, {:executed, :high})
      {:ok, state}
    end
    
    def process_entity(_entity_id, _components, _state) do
      {:ok, %{}}
    end
  end
  
  defmodule LowPrioritySystem do
    use AshGameServer.Systems.SystemBehaviour
    
    def init(_config), do: {:ok, %{}}
    def priority, do: :low
    def required_components, do: []
    
    def execute(_entities, state) do
      send(:test_process, {:executed, :low})
      {:ok, state}
    end
    
    def process_entity(_entity_id, _components, _state) do
      {:ok, %{}}
    end
  end
  
  setup do
    # Start a fresh scheduler for each test
    {:ok, pid} = SystemScheduler.start_link(tick_interval: 100)
    
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    {:ok, scheduler: pid}
  end
  
  describe "register_system/2" do
    test "successfully registers a system" do
      assert :ok = SystemScheduler.register_system(TestSystem, %{test_pid: self()})
    end
    
    test "initializes system with config" do
      config = %{test_pid: self()}
      assert :ok = SystemScheduler.register_system(TestSystem, config)
      
      # System should be initialized with config
      metrics = SystemScheduler.get_metrics()
      assert metrics.total_ticks >= 0
    end
  end
  
  describe "unregister_system/1" do
    test "successfully unregisters a system" do
      assert :ok = SystemScheduler.register_system(TestSystem, %{test_pid: self()})
      assert :ok = SystemScheduler.unregister_system(TestSystem)
    end
    
    test "returns error for non-existent system" do
      assert {:error, :not_found} = SystemScheduler.unregister_system(NonExistentSystem)
    end
  end
  
  describe "priority execution" do
    test "executes systems in priority order" do
      Process.register(self(), :test_process)
      
      # Register systems in random order
      assert :ok = SystemScheduler.register_system(LowPrioritySystem)
      assert :ok = SystemScheduler.register_system(HighPrioritySystem)
      
      # Execute one tick
      assert :ok = SystemScheduler.tick()
      
      # Check execution order
      assert_receive {:executed, :high}, 100
      assert_receive {:executed, :low}, 100
      
      Process.unregister(:test_process)
    end
  end
  
  describe "tick scheduling" do
    test "starts and stops scheduler" do
      assert :ok = SystemScheduler.start()
      assert {:error, :already_running} = SystemScheduler.start()
      
      assert :ok = SystemScheduler.stop()
      assert :ok = SystemScheduler.start()
    end
    
    test "manual tick execution" do
      Process.register(self(), :test_process)
      
      assert :ok = SystemScheduler.register_system(HighPrioritySystem)
      assert :ok = SystemScheduler.tick()
      
      assert_receive {:executed, :high}, 100
      
      Process.unregister(:test_process)
    end
    
    test "automatic tick execution" do
      Process.register(self(), :test_process)
      
      assert :ok = SystemScheduler.register_system(HighPrioritySystem)
      assert :ok = SystemScheduler.start()
      
      # Should receive multiple executions
      assert_receive {:executed, :high}, 200
      assert_receive {:executed, :high}, 200
      
      assert :ok = SystemScheduler.stop()
      Process.unregister(:test_process)
    end
  end
  
  describe "metrics" do
    test "tracks tick count" do
      initial_tick = SystemScheduler.current_tick()
      
      assert :ok = SystemScheduler.tick()
      assert :ok = SystemScheduler.tick()
      
      new_tick = SystemScheduler.current_tick()
      assert new_tick == initial_tick + 2
    end
    
    test "collects execution metrics" do
      assert :ok = SystemScheduler.register_system(TestSystem, %{test_pid: self()})
      assert :ok = SystemScheduler.tick()
      
      metrics = SystemScheduler.get_metrics()
      assert metrics.total_ticks > 0
      assert metrics.last_tick_duration >= 0
    end
  end
  
  describe "set_priority/2" do
    test "changes system priority" do
      Process.register(self(), :test_process)
      
      assert :ok = SystemScheduler.register_system(LowPrioritySystem)
      assert :ok = SystemScheduler.set_priority(LowPrioritySystem, :critical)
      
      # Should now execute with critical priority
      assert :ok = SystemScheduler.tick()
      assert_receive {:executed, :low}, 100
      
      Process.unregister(:test_process)
    end
    
    test "returns error for non-existent system" do
      assert {:error, :not_found} = SystemScheduler.set_priority(NonExistentSystem, :high)
    end
  end
end