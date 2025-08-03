defmodule AshGameServer.Integration.JidoAgentIntegrationTest do
  @moduledoc """
  Integration tests for Jido agent lifecycle and interactions.
  Tests agent creation, state management, message passing, and ETS storage integration.
  """
  use ExUnit.Case, async: false
  
  alias AshGameServer.Agents.{GameAgent, NPCAgent, PlayerAgent}
  alias AshGameServer.Storage.Storage
  alias AshGameServer.Jido.AgentSupervisor
  
  setup do
    # Ensure storage is started
    {:ok, _} = Storage.start_link([])
    
    # Start agent supervisor
    {:ok, supervisor} = AgentSupervisor.start_link([])
    
    on_exit(fn ->
      Storage.clear()
    end)
    
    {:ok, supervisor: supervisor}
  end
  
  describe "agent lifecycle integration" do
    test "creates and initializes game agent with ETS storage", %{supervisor: supervisor} do
      # Create an entity for the agent
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :position, %{x: 0, y: 0, z: 0})
      Storage.add_component(entity_id, :health, %{current: 100, max: 100})
      
      # Start a game agent
      {:ok, agent_pid} = AgentSupervisor.start_agent(supervisor, GameAgent, %{
        entity_id: entity_id,
        name: "TestAgent"
      })
      
      assert Process.alive?(agent_pid)
      
      # Verify agent can access its entity data
      state = GameAgent.get_state(agent_pid)
      assert state.entity_id == entity_id
      
      # Verify agent registered in storage
      agent_entities = Storage.query_entities([:agent_controlled])
      assert entity_id in agent_entities
    end
    
    test "handles agent state transitions", %{supervisor: supervisor} do
      {:ok, entity_id} = Storage.create_entity()
      
      {:ok, agent_pid} = AgentSupervisor.start_agent(supervisor, NPCAgent, %{
        entity_id: entity_id,
        behavior: :patrol
      })
      
      # Initial state
      assert NPCAgent.get_behavior(agent_pid) == :patrol
      
      # Transition to combat
      :ok = NPCAgent.set_behavior(agent_pid, :combat)
      assert NPCAgent.get_behavior(agent_pid) == :combat
      
      # Verify state persisted in ETS
      {:ok, agent_state} = Storage.get_component(entity_id, :ai_state)
      assert agent_state.behavior == :combat
    end
    
    test "handles message passing between agents", %{supervisor: supervisor} do
      # Create two agents
      {:ok, entity1} = Storage.create_entity()
      {:ok, entity2} = Storage.create_entity()
      
      {:ok, agent1} = AgentSupervisor.start_agent(supervisor, PlayerAgent, %{
        entity_id: entity1,
        name: "Player1"
      })
      
      {:ok, agent2} = AgentSupervisor.start_agent(supervisor, PlayerAgent, %{
        entity_id: entity2,
        name: "Player2"
      })
      
      # Send message from agent1 to agent2
      PlayerAgent.send_message(agent1, agent2, {:chat, "Hello!"})
      
      # Verify message received
      messages = PlayerAgent.get_messages(agent2)
      assert length(messages) == 1
      assert hd(messages) == {:chat, "Hello!", from: entity1}
    end
    
    test "handles agent crash and recovery", %{supervisor: supervisor} do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :position, %{x: 10, y: 20, z: 0})
      
      {:ok, agent_pid} = AgentSupervisor.start_agent(supervisor, GameAgent, %{
        entity_id: entity_id,
        name: "CrashTest"
      })
      
      old_pid = agent_pid
      
      # Force crash
      Process.exit(agent_pid, :kill)
      
      # Wait for supervisor to restart
      Process.sleep(100)
      
      # Get new agent pid
      {:ok, new_agent_pid} = AgentSupervisor.get_agent(supervisor, entity_id)
      
      assert new_agent_pid != old_pid
      assert Process.alive?(new_agent_pid)
      
      # Verify state recovered from ETS
      state = GameAgent.get_state(new_agent_pid)
      assert state.entity_id == entity_id
      
      {:ok, position} = Storage.get_component(entity_id, :position)
      assert position.x == 10
      assert position.y == 20
    end
    
    test "handles concurrent agent operations", %{supervisor: supervisor} do
      # Create multiple agents
      agents = for i <- 1..10 do
        {:ok, entity_id} = Storage.create_entity()
        Storage.add_component(entity_id, :score, %{points: 0})
        
        {:ok, agent} = AgentSupervisor.start_agent(supervisor, GameAgent, %{
          entity_id: entity_id,
          name: "Agent#{i}"
        })
        
        {entity_id, agent}
      end
      
      # Concurrent updates
      tasks = Enum.map(agents, fn {entity_id, agent} ->
        Task.async(fn ->
          for _ <- 1..100 do
            GameAgent.update_score(agent, 1)
          end
          entity_id
        end)
      end)
      
      # Wait for all tasks
      entity_ids = Task.await_many(tasks)
      
      # Verify all updates applied
      for entity_id <- entity_ids do
        {:ok, score} = Storage.get_component(entity_id, :score)
        assert score.points == 100
      end
    end
  end
  
  describe "agent-storage integration" do
    test "agent updates reflect in ETS storage", %{supervisor: supervisor} do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :position, %{x: 0, y: 0, z: 0})
      
      {:ok, agent} = AgentSupervisor.start_agent(supervisor, GameAgent, %{
        entity_id: entity_id,
        name: "StorageTest"
      })
      
      # Agent updates position
      GameAgent.move_to(agent, %{x: 50, y: 75, z: 10})
      
      # Verify in storage
      {:ok, position} = Storage.get_component(entity_id, :position)
      assert position.x == 50
      assert position.y == 75
      assert position.z == 10
    end
    
    test "storage updates visible to agents", %{supervisor: supervisor} do
      {:ok, entity_id} = Storage.create_entity()
      Storage.add_component(entity_id, :health, %{current: 100, max: 100})
      
      {:ok, agent} = AgentSupervisor.start_agent(supervisor, GameAgent, %{
        entity_id: entity_id,
        name: "HealthTest"
      })
      
      # External update to storage
      Storage.update_component(entity_id, :health, %{current: 50, max: 100})
      
      # Agent should see update
      health = GameAgent.get_health(agent)
      assert health.current == 50
    end
  end
end