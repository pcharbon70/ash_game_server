defmodule AshGameServer.Jido.SignalRouter do
  @moduledoc """
  CloudEvents-compliant signal router for agent communication.
  
  This module handles:
  - Signal routing and transformation
  - CloudEvents format compliance
  - Integration with Phoenix PubSub
  - Signal persistence and monitoring
  """
  use GenServer
  require Logger

  @router_name AshGameServer.Jido.SignalRouter

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @router_name)
  end

  @doc """
  Route a signal to its destination(s).
  """
  def route_signal(signal) do
    GenServer.cast(@router_name, {:route_signal, signal})
  end

  @doc """
  Subscribe to signals of a specific type.
  """
  def subscribe(signal_type, subscriber_pid \\ self()) when is_atom(signal_type) do
    topic = signal_topic(signal_type)
    Phoenix.PubSub.subscribe(AshGameServer.PubSub, topic)
    GenServer.call(@router_name, {:subscribe, signal_type, subscriber_pid})
  end

  @doc """
  Unsubscribe from signals of a specific type.
  """
  def unsubscribe(signal_type, subscriber_pid \\ self()) when is_atom(signal_type) do
    topic = signal_topic(signal_type)
    Phoenix.PubSub.unsubscribe(AshGameServer.PubSub, topic)
    GenServer.call(@router_name, {:unsubscribe, signal_type, subscriber_pid})
  end

  @doc """
  Create a CloudEvents-compliant signal.
  """
  def create_signal(type, source, data, opts \\ []) do
    %{
      specversion: "1.0",
      type: to_string(type),
      source: to_string(source),
      id: Keyword.get(opts, :id, generate_signal_id()),
      time: Keyword.get(opts, :time, DateTime.utc_now()),
      datacontenttype: Keyword.get(opts, :datacontenttype, "application/json"),
      data: data,
      # Game server specific extensions
      subject: Keyword.get(opts, :subject),
      agent_id: Keyword.get(opts, :agent_id),
      correlation_id: Keyword.get(opts, :correlation_id)
    }
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    state = %{
      subscriptions: %{},
      signal_count: 0,
      last_signal_time: nil
    }

    Logger.info("Signal router started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:route_signal, signal}, state) do
    # Validate CloudEvents format
    case validate_signal(signal) do
      {:ok, validated_signal} ->
        route_validated_signal(validated_signal)
        
        new_state = %{
          state | 
          signal_count: state.signal_count + 1,
          last_signal_time: DateTime.utc_now()
        }
        
        {:noreply, new_state}
      
      {:error, reason} ->
        Logger.warning("Invalid signal format: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:subscribe, signal_type, subscriber_pid}, _from, state) do
    subscriptions = Map.get(state.subscriptions, signal_type, MapSet.new())
    new_subscriptions = MapSet.put(subscriptions, subscriber_pid)
    
    new_state = %{
      state | 
      subscriptions: Map.put(state.subscriptions, signal_type, new_subscriptions)
    }
    
    Logger.debug("Subscribed #{inspect(subscriber_pid)} to #{signal_type}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, signal_type, subscriber_pid}, _from, state) do
    subscriptions = Map.get(state.subscriptions, signal_type, MapSet.new())
    new_subscriptions = MapSet.delete(subscriptions, subscriber_pid)
    
    new_state = %{
      state | 
      subscriptions: Map.put(state.subscriptions, signal_type, new_subscriptions)
    }
    
    Logger.debug("Unsubscribed #{inspect(subscriber_pid)} from #{signal_type}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:signal_metrics, state) do
    # Emit telemetry for signal processing
    :telemetry.execute(
      [:ash_game_server, :jido, :signal_router, :metrics],
      %{
        signal_count: state.signal_count,
        subscription_count: map_size(state.subscriptions)
      },
      %{last_signal_time: state.last_signal_time}
    )
    
    # Schedule next metrics emission
    Process.send_after(self(), :signal_metrics, 10_000)
    {:noreply, state}
  end

  # Private functions

  defp route_validated_signal(signal) do
    signal_type = String.to_atom(signal.type)
    topic = signal_topic(signal_type)
    
    # Broadcast via Phoenix PubSub
    Phoenix.PubSub.broadcast(AshGameServer.PubSub, topic, {:signal, signal})
    
    Logger.debug("Routed signal: #{signal.type} (#{signal.id})")
  end

  defp validate_signal(signal) when is_map(signal) do
    required_fields = [:specversion, :type, :source, :id]
    
    case Enum.all?(required_fields, &Map.has_key?(signal, &1)) do
      true -> {:ok, signal}
      false -> {:error, :missing_required_fields}
    end
  end
  defp validate_signal(_), do: {:error, :invalid_format}

  defp signal_topic(signal_type) do
    "signals:#{signal_type}"
  end

  defp generate_signal_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end