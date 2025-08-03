defmodule AshGameServer.AshResourcesTest do
  use ExUnit.Case, async: false
  
  alias AshGameServer.Players.Player
  alias AshGameServer.GameCore.GameSession

  setup do
    # Start repo and any other necessary services
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AshGameServer.Repo)
    :ok
  end

  describe "Player resource operations" do
    test "create player with valid attributes" do
      # Create a player
      result = Player.create("testuser", display_name: "Test Player")
      
      assert {:ok, player} = result
      assert player.username == "testuser"
      assert player.display_name == "Test Player"
      assert player.status == :offline
      assert player.level == 1
      assert player.experience_points == 0
      assert is_map(player.stats)
      assert player.stats.health == 100
    end

    test "create player fails with invalid username" do
      # Try to create with short username
      result = Player.create("ab")
      assert {:error, %Ash.Error.Invalid{}} = result
      
      # Try to create with invalid characters
      result = Player.create("test user!")
      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "username uniqueness is enforced" do
      # Create first player
      {:ok, _player1} = Player.create("uniqueuser")
      
      # Try to create second player with same username
      result = Player.create("uniqueuser")
      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "get player by id and username" do
      {:ok, player} = Player.create("gettest", display_name: "Get Test")
      
      # Get by ID
      found_player = Player.get(player.id)
      assert found_player.username == "gettest"
      
      # Get by username
      found_player = Player.get_by_username("gettest")
      assert found_player.id == player.id
    end

    test "update player status" do
      {:ok, player} = Player.create("statustest")
      
      # Update status to online
      {:ok, updated_player} = Player.update_status(player, status: :online)
      assert updated_player.status == :online
      assert updated_player.last_seen_at != nil
      
      # Update status to offline
      {:ok, updated_player} = Player.update_status(updated_player, status: :offline)
      assert updated_player.status == :offline
    end

    test "add experience and level progression" do
      {:ok, player} = Player.create("exptest")
      
      # Add some experience
      {:ok, updated_player} = Player.add_experience(player, amount: 500)
      assert updated_player.experience_points == 500
      assert updated_player.level == 1  # Still level 1
      
      # Add enough experience to level up
      {:ok, updated_player} = Player.add_experience(updated_player, amount: 600)
      assert updated_player.experience_points == 1100
      assert updated_player.level == 2  # Should be level 2 now
    end

    test "update player stats" do
      {:ok, player} = Player.create("statstest")
      
      # Update specific stats
      stat_changes = %{strength: 15, intelligence: 12}
      {:ok, updated_player} = Player.update_stats(player, stat_changes: stat_changes)
      
      assert updated_player.stats.strength == 15
      assert updated_player.stats.intelligence == 12
      assert updated_player.stats.health == 100  # Unchanged
    end

    test "player validations work correctly" do
      {:ok, player} = Player.create("validtest")
      
      # Try to update with invalid level
      result = Player.update(player, level: 0)
      assert {:error, %Ash.Error.Invalid{}} = result
      
      # Try to update with negative experience
      result = Player.update(player, experience_points: -10)
      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "soft delete player" do
      {:ok, player} = Player.create("deletetest")
      
      # Delete player (soft delete)
      {:ok, deleted_player} = Player.delete(player)
      assert deleted_player.deleted_at != nil
      
      # Player should not be found in normal queries
      found_player = Player.get_by_username("deletetest")
      assert found_player == nil
    end

    test "list players" do
      # Create multiple players
      {:ok, _player1} = Player.create("listtest1")
      {:ok, _player2} = Player.create("listtest2")
      {:ok, _player3} = Player.create("listtest3")
      
      # List all players
      players = Player.list()
      assert length(players) >= 3
      
      usernames = Enum.map(players, & &1.username)
      assert "listtest1" in usernames
      assert "listtest2" in usernames
      assert "listtest3" in usernames
    end
  end

  describe "GameSession resource operations" do
    test "create game session with valid attributes" do
      result = GameSession.create("Test Game", 
        game_type: :standard, 
        max_players: 6,
        config: %{map: "test_map", difficulty: "easy"}
      )
      
      assert {:ok, session} = result
      assert session.name == "Test Game"
      assert session.game_type == :standard
      assert session.max_players == 6
      assert session.current_players == 0
      assert session.status == :waiting
      assert session.config.map == "test_map"
    end

    test "game session status transitions" do
      {:ok, session} = GameSession.create("Status Test")
      
      # Initially waiting
      assert session.status == :waiting
      
      # Cannot start with 0 players
      result = GameSession.start(session)
      assert {:error, %Ash.Error.Invalid{}} = result
      
      # Add a player first
      {:ok, session_with_player} = GameSession.add_player(session, player_id: Ash.UUID.generate())
      assert session_with_player.current_players == 1
      
      # Now can start
      {:ok, started_session} = GameSession.start(session_with_player)
      assert started_session.status == :active
      assert started_session.started_at != nil
      
      # Can pause
      {:ok, paused_session} = GameSession.pause(started_session)
      assert paused_session.status == :paused
      
      # Can resume
      {:ok, resumed_session} = GameSession.resume(paused_session)
      assert resumed_session.status == :active
      
      # Can complete
      final_state = %{winner: "player1", score: 100}
      {:ok, completed_session} = GameSession.complete(resumed_session, final_state: final_state)
      assert completed_session.status == :completed
      assert completed_session.ended_at != nil
      assert completed_session.game_state == final_state
    end

    test "game session player management" do
      {:ok, session} = GameSession.create("Player Test", max_players: 2)
      
      # Add first player
      player1_id = Ash.UUID.generate()
      {:ok, session} = GameSession.add_player(session, player_id: player1_id)
      assert session.current_players == 1
      
      # Add second player
      player2_id = Ash.UUID.generate()
      {:ok, session} = GameSession.add_player(session, player_id: player2_id)
      assert session.current_players == 2
      
      # Cannot add third player (session is full)
      player3_id = Ash.UUID.generate()
      result = GameSession.add_player(session, player_id: player3_id)
      assert {:error, %Ash.Error.Invalid{}} = result
      
      # Remove a player
      {:ok, session} = GameSession.remove_player(session, player_id: player1_id)
      assert session.current_players == 1
    end

    test "game session validations" do
      # Cannot create with invalid max_players
      result = GameSession.create("Invalid Test", max_players: 0)
      assert {:error, %Ash.Error.Invalid{}} = result
      
      {:ok, session} = GameSession.create("Valid Test", max_players: 2)
      
      # Cannot set current_players > max_players
      result = GameSession.update(session, current_players: 5)
      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "game session calculations" do
      {:ok, session} = GameSession.create("Calc Test", max_players: 4)
      
      # Add players to test is_full calculation
      player1_id = Ash.UUID.generate()
      {:ok, session} = GameSession.add_player(session, player_id: player1_id)
      
      # Reload to get calculations
      session = GameSession.get(session.id)
      refute session.is_full
      
      # Add more players
      for _i <- 1..3 do
        player_id = Ash.UUID.generate()
        {:ok, session} = GameSession.add_player(session, player_id: player_id)
      end
      
      # Should be full now
      session = GameSession.get(session.id)
      assert session.is_full
      
      # Test is_active calculation
      refute session.is_active
      
      {:ok, started_session} = GameSession.start(session)
      started_session = GameSession.get(started_session.id)
      assert started_session.is_active
    end

    test "update game state during active session" do
      {:ok, session} = GameSession.create("State Test")
      
      # Add a player and start
      player_id = Ash.UUID.generate()
      {:ok, session} = GameSession.add_player(session, player_id: player_id)
      {:ok, session} = GameSession.start(session)
      
      # Update game state
      state_changes = %{round: 1, turn: "player1", board: %{}}
      {:ok, updated_session} = GameSession.update_game_state(session, state_changes: state_changes)
      
      assert updated_session.game_state.round == 1
      assert updated_session.game_state.turn == "player1"
    end

    test "cannot update game state when not active" do
      {:ok, session} = GameSession.create("Inactive State Test")
      
      # Try to update game state while waiting
      state_changes = %{round: 1}
      result = GameSession.update_game_state(session, state_changes: state_changes)
      assert {:error, %Ash.Error.Invalid{}} = result
    end

    test "cancel game session" do
      {:ok, session} = GameSession.create("Cancel Test")
      
      # Can cancel while waiting
      {:ok, cancelled_session} = GameSession.cancel(session)
      assert cancelled_session.status == :cancelled
      assert cancelled_session.ended_at != nil
      
      # Create another session and start it
      {:ok, session2} = GameSession.create("Cancel Active Test")
      player_id = Ash.UUID.generate()
      {:ok, session2} = GameSession.add_player(session2, player_id: player_id)
      {:ok, session2} = GameSession.start(session2)
      
      # Can cancel while active
      {:ok, cancelled_session2} = GameSession.cancel(session2)
      assert cancelled_session2.status == :cancelled
    end

    test "soft delete game session" do
      {:ok, session} = GameSession.create("Delete Test")
      
      # Delete session (soft delete)
      {:ok, deleted_session} = GameSession.delete(session)
      assert deleted_session.deleted_at != nil
      
      # Session should not be found in normal queries
      found_session = GameSession.get(session.id)
      assert found_session == nil
    end

    test "list game sessions" do
      # Create multiple sessions
      {:ok, _session1} = GameSession.create("List Test 1")
      {:ok, _session2} = GameSession.create("List Test 2")
      {:ok, _session3} = GameSession.create("List Test 3")
      
      # List all sessions
      sessions = GameSession.list()
      assert length(sessions) >= 3
      
      names = Enum.map(sessions, & &1.name)
      assert "List Test 1" in names
      assert "List Test 2" in names
      assert "List Test 3" in names
    end
  end

  describe "Resource integration" do
    test "resources use consistent patterns" do
      # Both resources should have similar structure
      assert function_exported?(Player, :create, 1)
      assert function_exported?(Player, :get, 1)
      assert function_exported?(Player, :list, 0)
      assert function_exported?(Player, :update, 2)
      assert function_exported?(Player, :delete, 1)
      
      assert function_exported?(GameSession, :create, 1)
      assert function_exported?(GameSession, :get, 1)
      assert function_exported?(GameSession, :list, 0)
      assert function_exported?(GameSession, :update, 2)
      assert function_exported?(GameSession, :delete, 1)
    end

    test "resources support soft delete" do
      {:ok, player} = Player.create("softtest")
      {:ok, session} = GameSession.create("Soft Test")
      
      # Both should support soft delete
      {:ok, deleted_player} = Player.delete(player)
      {:ok, deleted_session} = GameSession.delete(session)
      
      assert deleted_player.deleted_at != nil
      assert deleted_session.deleted_at != nil
    end

    test "resources have audit fields from base" do
      {:ok, player} = Player.create("audittest")
      {:ok, session} = GameSession.create("Audit Test")
      
      # Both should have audit fields
      assert player.created_at != nil
      assert player.updated_at != nil
      assert session.created_at != nil
      assert session.updated_at != nil
    end
  end
end