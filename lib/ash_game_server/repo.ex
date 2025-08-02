defmodule AshGameServer.Repo do
  use AshPostgres.Repo, otp_app: :ash_game_server

  # Minimum PostgreSQL version required
  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end

  # Installed extensions for game server functionality
  def installed_extensions do
    # Add any PostgreSQL extensions needed
    ["uuid-ossp", "citext", "pg_trgm", "ash-functions"]
  end
end