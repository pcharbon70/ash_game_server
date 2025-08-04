defmodule AshGameServer.Jido.BaseAgent do
  @moduledoc """
  Base agent module for game server agents.

  This module provides common functionality for all game agents:
  - State validation and management
  - Lifecycle hooks
  - Error handling
  - Integration with registry and monitoring
  """

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use Jido.Agent, opts

      require Logger

      # Automatically register with the agent registry on start
      def on_start(state, context) do
        agent_id = context[:id] || generate_agent_id()

        case AshGameServer.Jido.AgentRegistry.register_agent(agent_id, self(), %{
          module: __MODULE__,
          started_at: DateTime.utc_now(),
          type: :game_agent
        }) do
          {:ok, _agent_info} ->
            # Start monitoring
            AshGameServer.Jido.AgentMonitor.monitor_agent(agent_id, self())

            Logger.info("Game agent started: #{agent_id}")
            {:ok, Map.put(state, :agent_id, agent_id)}

          {:error, reason} ->
            Logger.error("Failed to register agent: #{inspect(reason)}")
            {:error, reason}
        end
      end

      # Automatically unregister on stop
      def on_stop(_reason, state, _context) do
        if agent_id = Map.get(state, :agent_id) do
          AshGameServer.Jido.AgentRegistry.unregister_agent(agent_id)
          AshGameServer.Jido.AgentMonitor.unmonitor_agent(agent_id)
          Logger.info("Game agent stopped: #{agent_id}")
        end

        :ok
      end

      # Enhanced error handling
      @impl true
      def on_error(agent, error) do
        Logger.warning("Agent error: #{inspect(error)}")

        # Emit telemetry
        :telemetry.execute(
          [:ash_game_server, :jido, :agent, :error],
          %{count: 1},
          %{
            agent_id: Map.get(agent.state, :agent_id),
            module: __MODULE__,
            error: error
          }
        )

        case error do
          %{type: :validation_error} ->
            # Reset to a safe state
            safe_state = get_safe_state(agent.state)
            {:ok, %{agent | state: safe_state}}

          %{type: :temporary_error} ->
            # Log and continue
            {:ok, agent}

          _ ->
            # Re-raise for supervisor handling
            {:error, error}
        end
      end

      # Signal handling integration
      def handle_signal(signal, state) do
        Logger.debug("Received signal: #{signal.type}")

        # Emit telemetry
        :telemetry.execute(
          [:ash_game_server, :jido, :agent, :signal_received],
          %{count: 1},
          %{
            agent_id: Map.get(state, :agent_id),
            signal_type: signal.type,
            signal_source: signal.source
          }
        )

        # Default implementation - can be overridden
        {:ok, state}
      end

      # Broadcast a signal from this agent
      def broadcast_signal(state, signal_type, data, opts \\ []) do
        agent_id = Map.get(state, :agent_id, "unknown")

        signal = AshGameServer.Jido.SignalRouter.create_signal(
          signal_type,
          agent_id,
          data,
          Keyword.merge(opts, [agent_id: agent_id])
        )

        AshGameServer.Jido.SignalRouter.route_signal(signal)
        signal
      end

      # Helper functions
      defp generate_agent_id do
        base = __MODULE__ |> Module.split() |> List.last() |> String.downcase()
        timestamp = System.unique_integer([:positive])
        "#{base}_#{timestamp}"
      end

      defp get_safe_state(_state) do
        # Default safe state - should be overridden by implementing modules
        %{status: :idle, agent_id: nil}
      end

      # Allow implementing modules to override these functions
      defoverridable on_error: 2, handle_signal: 2, get_safe_state: 1
    end
  end
end
