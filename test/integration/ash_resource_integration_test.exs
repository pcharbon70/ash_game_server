defmodule AshGameServer.Integration.AshResourceIntegrationTest do
  @moduledoc """
  Integration tests for Ash resources with ETS storage backing.
  Tests CRUD operations, PubSub notifications, transactions, and relationships.
  """
  use ExUnit.Case, async: false
  
  alias AshGameServer.Players.Player
  alias AshGameServer.GameCore.GameSession
  alias AshGameServer.Storage.Storage
  alias AshGameServer.Storage.PersistenceBridge
  
  setup do
    # Start storage
    {:ok, _} = Storage.start_link([])
    {:ok, _} = PersistenceBridge.start_link([])
    
    # Clean up after test
    on_exit(fn ->
      Storage.clear()
      # Clean database
      AshGameServer.Repo.delete_all(Player)
      AshGameServer.Repo.delete_all(GameSession)
    end)
    
    :ok
  end
  
  describe "resource CRUD with ETS backing" do
    test "creates player resource with ETS entity" do
      # Create player through Ash
      {:ok, player} = Player.create(%{
        username: "test_player",
        display_name: "Test Player"
      })
      
      assert player.username == "test_player"
      assert player.id
      
      # Verify ETS entity created
      entities = Storage.query_entities([:player_data])
      assert length(entities) > 0
      
      # Verify component data matches
      entity_id = hd(entities)
      {:ok, player_data} = Storage.get_component(entity_id, :player_data)
      assert player_data.username == "test_player"
      assert player_data.resource_id == player.id
    end
    
    test "updates sync between Ash and ETS" do
      {:ok, player} = Player.create(%{username: "update_test"})
      
      # Get ETS entity
      [entity_id] = Storage.query_entities([:player_data])
      
      # Update through Ash
      {:ok, updated} = Player.update(player, %{
        level: 5,
        experience_points: 500
      })
      
      assert updated.level == 5
      
      # Verify ETS updated
      {:ok, player_data} = Storage.get_component(entity_id, :player_data)
      assert player_data.level == 5
      assert player_data.experience_points == 500
    end
    
    test "deletes cascade to ETS" do
      {:ok, player} = Player.create(%{username: "delete_test"})
      [entity_id] = Storage.query_entities([:player_data])
      
      # Delete through Ash
      :ok = Player.delete(player)
      
      # Verify ETS entity removed
      assert Storage.get_entity(entity_id) == {:error, :not_found}
      entities = Storage.query_entities([:player_data])
      assert entities == []
    end
  end
  
  describe "PubSub notifications across components" do
    test "resource changes broadcast to subscribers" do
      # Subscribe to player updates
      Phoenix.PubSub.subscribe(AshGameServer.PubSub, "players:updates")
      
      # Create player
      {:ok, player} = Player.create(%{username: "pubsub_test"})
      
      # Should receive creation notification
      assert_receive {:player_created, %{id: player_id}}, 1000
      assert player_id == player.id
      
      # Update player
      {:ok, _} = Player.update_status(player, %{status: :online})
      
      # Should receive update notification
      assert_receive {:player_updated, %{id: ^player_id, status: :online}}, 1000
    end
    
    test "ETS changes trigger resource notifications" do
      {:ok, player} = Player.create(%{username: "ets_notify"})
      [entity_id] = Storage.query_entities([:player_data])
      
      Phoenix.PubSub.subscribe(AshGameServer.PubSub, "players:#{player.id}")
      
      # Update through ETS
      Storage.update_component(entity_id, :player_data, %{
        level: 10
      })
      
      # Should receive notification
      assert_receive {:component_updated, :player_data, %{level: 10}}, 1000
    end
  end
  
  describe "transaction handling" do
    test "atomic operations across Ash and ETS" do
      # Start transaction
      result = AshGameServer.Repo.transaction(fn ->
        # Create player
        {:ok, player} = Player.create(%{username: "transaction_test"})
        [entity_id] = Storage.query_entities([:player_data])
        
        # Add components in ETS
        Storage.add_component(entity_id, :inventory, %{items: [], capacity: 20})
        Storage.add_component(entity_id, :stats, %{strength: 10, agility: 10})
        
        # Simulate failure
        if player.username == "transaction_test" do
          AshGameServer.Repo.rollback(:test_rollback)
        end
        
        player
      end)
      
      # Transaction should have rolled back
      assert {:error, :test_rollback} = result
      
      # Verify nothing persisted
      players = Player.list()
      assert players == []
      
      # Verify ETS also rolled back
      entities = Storage.query_entities([:player_data])
      assert entities == []
    end
    
    test "successful transaction commits all changes" do
      result = AshGameServer.Repo.transaction(fn ->
        {:ok, player} = Player.create(%{username: "commit_test"})
        [entity_id] = Storage.query_entities([:player_data])
        
        Storage.add_component(entity_id, :position, %{x: 100, y: 200, z: 0})
        
        {:ok, session} = GameSession.create(%{
          name: "Test Game",
          max_players: 4
        })
        
        {player, session, entity_id}
      end)
      
      assert {:ok, {player, session, entity_id}} = result
      
      # Verify all persisted
      assert Player.get(player.id)
      assert GameSession.get(session.id)
      assert {:ok, _pos} = Storage.get_component(entity_id, :position)
    end
  end
  
  describe "resource relationships with ETS" do
    test "player-session relationship with entity associations" do
      {:ok, player} = Player.create(%{username: "relation_test"})
      [player_entity] = Storage.query_entities([:player_data])
      
      {:ok, session} = GameSession.create(%{
        name: "Multiplayer Game",
        max_players: 8
      })
      
      # Add player to session
      {:ok, _} = GameSession.add_player(session, %{player_id: player.id})
      
      # Create session entity
      {:ok, session_entity} = Storage.create_entity()
      Storage.add_component(session_entity, :session_data, %{
        resource_id: session.id,
        players: [player_entity]
      })
      
      # Query relationships
      {:ok, session_data} = Storage.get_component(session_entity, :session_data)
      assert player_entity in session_data.players
      
      # Verify bidirectional
      Storage.add_component(player_entity, :current_session, %{
        entity_id: session_entity,
        resource_id: session.id
      })
      
      {:ok, current} = Storage.get_component(player_entity, :current_session)
      assert current.entity_id == session_entity
    end
  end
  
  describe "query performance with ETS indexes" do
    test "bulk insert and indexed queries" do
      # Create many players
      players = for i <- 1..1000 do
        {:ok, player} = Player.create(%{
          username: "player_#{i}",
          level: rem(i, 100) + 1
        })
        player
      end
      
      # Time indexed query
      {time, high_level} = :timer.tc(fn ->
        Player.list(filter: [level: [greater_than: 90]])
      end)
      
      assert length(high_level) == 100
      # Should be very fast with ETS indexes (< 10ms)
      assert time < 10_000
    end
    
    test "complex queries with ETS optimization" do
      # Create players with various stats
      for i <- 1..100 do
        {:ok, _player} = Player.create(%{
          username: "complex_#{i}",
          level: rem(i, 20) + 1,
          experience_points: i * 100
        })
        
        [entity_id] = Storage.query_entities([:player_data])
        Storage.add_component(entity_id, :stats, %{
          strength: rem(i, 50),
          intelligence: rem(i, 40),
          agility: rem(i, 30)
        })
      end
      
      # Complex query combining Ash and ETS
      {time, results} = :timer.tc(fn ->
        # Get high-level players
        players = Player.list(filter: [level: [greater_than: 15]])
        
        # Filter by ETS components
        Enum.filter(players, fn player ->
          entities = Storage.query_entities([:player_data])
          entity = Enum.find(entities, fn e ->
            {:ok, data} = Storage.get_component(e, :player_data)
            data.resource_id == player.id
          end)
          
          if entity do
            {:ok, stats} = Storage.get_component(entity, :stats)
            stats.strength > 25
          else
            false
          end
        end)
      end)
      
      assert length(results) > 0
      # Should complete quickly even with complex filtering
      assert time < 50_000
    end
  end
end