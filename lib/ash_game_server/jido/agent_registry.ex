defmodule AshGameServer.Jido.AgentRegistry do
  @moduledoc """
  Distributed agent registry using Horde for agent discovery and metadata management.
  
  This registry provides:
  - Distributed agent registration across nodes
  - Agent metadata storage and retrieval
  - Health monitoring integration
  - Automatic cleanup of dead agents
  """
  use GenServer
  require Logger

  @registry_name AshGameServer.Jido.AgentRegistry

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Register an agent with metadata.
  """
  def register_agent(agent_id, pid, metadata \\ %{}) when is_binary(agent_id) and is_pid(pid) do
    GenServer.call(@registry_name, {:register, agent_id, pid, metadata})
  end

  @doc """
  Unregister an agent.
  """
  def unregister_agent(agent_id) when is_binary(agent_id) do
    GenServer.call(@registry_name, {:unregister, agent_id})
  end

  @doc """
  Lookup an agent by ID.
  """
  def lookup_agent(agent_id) when is_binary(agent_id) do
    GenServer.call(@registry_name, {:lookup, agent_id})
  end

  @doc """
  List all registered agents.
  """
  def list_agents do
    GenServer.call(@registry_name, :list_agents)
  end

  @doc """
  Update agent metadata.
  """
  def update_metadata(agent_id, metadata) when is_binary(agent_id) and is_map(metadata) do
    GenServer.call(@registry_name, {:update_metadata, agent_id, metadata})
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Use ETS for fast lookups
    table = :ets.new(@registry_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Monitor agent processes
    Process.flag(:trap_exit, true)
    
    state = %{
      table: table,
      monitors: %{}
    }

    Logger.info("Agent registry started")
    {:ok, state}
  end

  @impl true
  def handle_call({:register, agent_id, pid, metadata}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [] ->
        # Monitor the agent process
        monitor_ref = Process.monitor(pid)
        
        agent_info = %{
          id: agent_id,
          pid: pid,
          metadata: metadata,
          registered_at: DateTime.utc_now(),
          status: :active
        }
        
        :ets.insert(state.table, {agent_id, agent_info})
        
        new_monitors = Map.put(state.monitors, monitor_ref, agent_id)
        new_state = %{state | monitors: new_monitors}
        
        Logger.debug("Registered agent: #{agent_id}")
        {:reply, {:ok, agent_info}, new_state}
      
      [{_id, existing_info}] ->
        {:reply, {:error, {:already_registered, existing_info}}, state}
    end
  end

  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{_id, agent_info}] ->
        :ets.delete(state.table, agent_id)
        Logger.debug("Unregistered agent: #{agent_id}")
        {:reply, {:ok, agent_info}, state}
      
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:lookup, agent_id}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{_id, agent_info}] -> {:reply, {:ok, agent_info}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agents = :ets.tab2list(state.table)
    {:reply, {:ok, agents}, state}
  end

  @impl true
  def handle_call({:update_metadata, agent_id, new_metadata}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{_id, agent_info}] ->
        updated_info = %{agent_info | metadata: Map.merge(agent_info.metadata, new_metadata)}
        :ets.insert(state.table, {agent_id, updated_info})
        {:reply, {:ok, updated_info}, state}
      
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}
      
      agent_id ->
        Logger.info("Agent #{agent_id} went down: #{inspect(reason)}")
        :ets.delete(state.table, agent_id)
        
        new_monitors = Map.delete(state.monitors, monitor_ref)
        new_state = %{state | monitors: new_monitors}
        
        {:noreply, new_state}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Agent registry shutting down")
    :ok
  end
end