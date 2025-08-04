defmodule AshGameServer.Telemetry do
  @moduledoc """
  Telemetry supervisor for metrics and monitoring.
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Jido Agent Metrics
      counter("ash_game_server.jido.agent.error.count"),
      counter("ash_game_server.jido.agent.signal_received.count"),
      counter("ash_game_server.jido.agent_monitor.agent_down.count"),
      last_value("ash_game_server.jido.signal_router.metrics.signal_count"),
      last_value("ash_game_server.jido.signal_router.metrics.subscription_count"),

      # Game Server Metrics (to be added as we implement features)
      # summary("game.tick.duration", unit: {:native, :millisecond}),
      # counter("game.player.join"),
      # counter("game.player.leave"),
      # last_value("game.players.online")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # {AshGameServer.Metrics, :dispatch_stats, []}
    ]
  end
end
