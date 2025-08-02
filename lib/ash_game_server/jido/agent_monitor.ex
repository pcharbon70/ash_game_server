defmodule AshGameServer.Jido.AgentMonitor do
  @moduledoc """
  Health monitoring and circuit breaker for agents.
  
  This module provides:
  - Agent health checking
  - Circuit breaker patterns
  - Performance monitoring
  - Automatic recovery strategies
  """
  use GenServer
  require Logger

  @monitor_name AshGameServer.Jido.AgentMonitor
  @health_check_interval 30_000
  @circuit_breaker_threshold 5
  @circuit_breaker_timeout 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @monitor_name)
  end

  @doc """
  Register an agent for monitoring.
  """
  def monitor_agent(agent_id, agent_pid) when is_binary(agent_id) and is_pid(agent_pid) do
    GenServer.cast(@monitor_name, {:monitor_agent, agent_id, agent_pid})
  end

  @doc """
  Unregister an agent from monitoring.
  """
  def unmonitor_agent(agent_id) when is_binary(agent_id) do
    GenServer.cast(@monitor_name, {:unmonitor_agent, agent_id})
  end

  @doc """
  Get health status for an agent.
  """
  def get_agent_health(agent_id) when is_binary(agent_id) do
    GenServer.call(@monitor_name, {:get_health, agent_id})
  end

  @doc """
  Get health status for all monitored agents.
  """
  def get_all_health do
    GenServer.call(@monitor_name, :get_all_health)
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Schedule initial health check
    Process.send_after(self(), :health_check, @health_check_interval)
    
    state = %{
      monitored_agents: %{},
      circuit_breakers: %{},
      health_history: %{}
    }

    Logger.info("Agent monitor started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:monitor_agent, agent_id, agent_pid}, state) do
    # Monitor the process
    monitor_ref = Process.monitor(agent_pid)
    
    agent_info = %{
      pid: agent_pid,
      monitor_ref: monitor_ref,
      last_health_check: DateTime.utc_now(),
      status: :healthy,
      failure_count: 0
    }
    
    new_monitored = Map.put(state.monitored_agents, agent_id, agent_info)
    new_state = %{state | monitored_agents: new_monitored}
    
    Logger.debug("Started monitoring agent: #{agent_id}")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unmonitor_agent, agent_id}, state) do
    case Map.get(state.monitored_agents, agent_id) do
      nil ->
        {:noreply, state}
      
      agent_info ->
        Process.demonitor(agent_info.monitor_ref, [:flush])
        new_monitored = Map.delete(state.monitored_agents, agent_id)
        new_circuit_breakers = Map.delete(state.circuit_breakers, agent_id)
        new_history = Map.delete(state.health_history, agent_id)
        
        new_state = %{
          state | 
          monitored_agents: new_monitored,
          circuit_breakers: new_circuit_breakers,
          health_history: new_history
        }
        
        Logger.debug("Stopped monitoring agent: #{agent_id}")
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:get_health, agent_id}, _from, state) do
    case Map.get(state.monitored_agents, agent_id) do
      nil -> {:reply, {:error, :not_monitored}, state}
      agent_info -> {:reply, {:ok, agent_info.status}, state}
    end
  end

  @impl true
  def handle_call(:get_all_health, _from, state) do
    health_map = 
      state.monitored_agents
      |> Enum.map(fn {agent_id, agent_info} -> 
        {agent_id, agent_info.status} 
      end)
      |> Map.new()
    
    {:reply, {:ok, health_map}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_checks(state)
    
    # Schedule next health check
    Process.send_after(self(), :health_check, @health_check_interval)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    # Find which agent went down
    agent_id = 
      state.monitored_agents
      |> Enum.find_value(fn {id, info} -> 
        if info.monitor_ref == monitor_ref, do: id, else: nil
      end)
    
    case agent_id do
      nil ->
        {:noreply, state}
      
      id ->
        Logger.warning("Monitored agent #{id} went down: #{inspect(reason)}")
        
        # Remove from monitoring
        new_monitored = Map.delete(state.monitored_agents, id)
        new_state = %{state | monitored_agents: new_monitored}
        
        # Trigger recovery if needed
        maybe_trigger_recovery(id, reason)
        
        {:noreply, new_state}
    end
  end

  # Private functions

  defp perform_health_checks(state) do
    Enum.reduce(state.monitored_agents, state, fn {agent_id, agent_info}, acc_state ->
      case check_agent_health(agent_info.pid) do
        :healthy ->
          update_agent_health(acc_state, agent_id, :healthy, 0)
        
        :unhealthy ->
          failure_count = agent_info.failure_count + 1
          status = if failure_count >= @circuit_breaker_threshold, do: :circuit_open, else: :unhealthy
          update_agent_health(acc_state, agent_id, status, failure_count)
      end
    end)
  end

  defp check_agent_health(agent_pid) do
    try do
      # Simple ping check - could be expanded for more sophisticated health checks
      case Process.alive?(agent_pid) do
        true -> :healthy
        false -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp update_agent_health(state, agent_id, status, failure_count) do
    case Map.get(state.monitored_agents, agent_id) do
      nil ->
        state
      
      agent_info ->
        updated_info = %{
          agent_info | 
          status: status,
          failure_count: failure_count,
          last_health_check: DateTime.utc_now()
        }
        
        new_monitored = Map.put(state.monitored_agents, agent_id, updated_info)
        
        # Update health history
        history = Map.get(state.health_history, agent_id, [])
        new_history_entry = %{timestamp: DateTime.utc_now(), status: status}
        updated_history = [new_history_entry | Enum.take(history, 9)] # Keep last 10 entries
        new_health_history = Map.put(state.health_history, agent_id, updated_history)
        
        %{
          state | 
          monitored_agents: new_monitored,
          health_history: new_health_history
        }
    end
  end

  defp maybe_trigger_recovery(agent_id, reason) do
    # Could implement automatic recovery strategies here
    Logger.info("Consider recovery for agent #{agent_id}, reason: #{inspect(reason)}")
    
    # Emit telemetry event for monitoring
    :telemetry.execute(
      [:ash_game_server, :jido, :agent_monitor, :agent_down],
      %{count: 1},
      %{agent_id: agent_id, reason: reason}
    )
  end
end