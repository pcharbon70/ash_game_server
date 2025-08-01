import Config

# Configure your database
config :ash_game_server, AshGameServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ash_game_server_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :phoenix, :plug_init_mode, :runtime

# Enable dev routes for Phoenix
config :phoenix,
  debug_errors: true,
  code_reloader: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20