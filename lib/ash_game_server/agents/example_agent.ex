defmodule AshGameServer.Agents.ExampleAgent do
  @moduledoc """
  Example game agent for testing Jido integration.
  
  This agent demonstrates:
  - Basic agent lifecycle
  - State management with validation
  - Signal handling
  - Action execution
  """
  use AshGameServer.Jido.BaseAgent,
    name: "example_agent",
    description: "Example agent for testing game server integration",
    schema: [
      status: [type: :atom, values: [:idle, :active, :processing], default: :idle],
      data: [type: :map, default: %{}],
      message_count: [type: :integer, default: 0]
    ],
    actions: [
      AshGameServer.Actions.ProcessMessage,
      AshGameServer.Actions.UpdateStatus
    ]

  def on_before_validate_state(state) do
    # Validate state transitions
    case {Map.get(state, :status), state[:status]} do
      {old_status, new_status} when old_status != new_status ->
        if valid_transition?(old_status, new_status) do
          {:ok, state}
        else
          {:error, {:invalid_transition, old_status, new_status}}
        end
      
      _ ->
        {:ok, state}
    end
  end

  def handle_signal(signal, state) do
    case signal.type do
      "message.received" ->
        # Process incoming message
        new_count = Map.get(state, :message_count, 0) + 1
        new_state = Map.put(state, :message_count, new_count)
        
        # Broadcast response signal
        _response_signal = broadcast_signal(
          new_state,
          :message_processed,
          %{
            original_message: signal.data,
            processed_at: DateTime.utc_now(),
            total_messages: new_count
          }
        )
        
        {:ok, new_state}
      
      "status.update" ->
        # Update agent status
        new_status = signal.data[:status] || :idle
        new_state = Map.put(state, :status, new_status)
        {:ok, new_state}
      
      _ ->
        # Call parent implementation for unhandled signals
        super(signal, state)
    end
  end

  def get_safe_state(_state) do
    %{
      status: :idle,
      data: %{},
      message_count: 0,
      agent_id: nil
    }
  end

  # Public API functions

  @doc """
  Send a message to this agent.
  """
  def send_message(agent_pid, message) when is_pid(agent_pid) do
    signal = AshGameServer.Jido.SignalRouter.create_signal(
      :message_received,
      "external",
      %{message: message, sent_at: DateTime.utc_now()}
    )
    
    send(agent_pid, {:signal, signal})
  end

  @doc """
  Update the agent's status.
  """
  def update_status(agent_pid, new_status) when is_pid(agent_pid) and is_atom(new_status) do
    signal = AshGameServer.Jido.SignalRouter.create_signal(
      :status_update,
      "external",
      %{status: new_status, updated_at: DateTime.utc_now()}
    )
    
    send(agent_pid, {:signal, signal})
  end

  # Private functions

  defp valid_transition?(from, to) do
    valid_transitions = %{
      :idle => [:active, :processing],
      :active => [:idle, :processing],
      :processing => [:idle, :active]
    }
    
    to in Map.get(valid_transitions, from, [])
  end
end