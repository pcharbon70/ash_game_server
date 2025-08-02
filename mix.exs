defmodule AshGameServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_game_server,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {AshGameServer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core Dependencies
      {:jido, "~> 1.2.0"},
      {:ash, "~> 3.5.33"},
      {:ash_postgres, "~> 2.6.14"},
      {:spark, "~> 2.2.67"},
      
      # Supporting Libraries
      {:phoenix, "~> 1.7.21"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ash_commanded, "~> 0.1.0"},
      {:horde, "~> 0.9.1"},
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      
      # Development Tools
      {:igniter, "~> 0.6.4", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end