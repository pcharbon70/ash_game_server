defmodule AshGameServer.Components.GameplayTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.Components.Gameplay.{Health, Inventory, Stats}
  alias AshGameServer.Components.Network.NetworkID
  
  describe "Health component" do
    test "validates health values correctly" do
      valid = %Health{current: 50.0, maximum: 100.0}
      assert :ok = Health.validate(valid)
      
      invalid = %Health{current: 150.0, maximum: 100.0}
      assert {:error, _} = Health.validate(invalid)
    end
    
    test "applies damage with resistance" do
      health = %Health{
        current: 100.0,
        maximum: 100.0,
        damage_resistance: 0.5
      }
      
      damaged = Health.take_damage(health, 50.0)
      assert damaged.current == 75.0  # 50% resistance
    end
    
    test "heals up to maximum" do
      health = %Health{current: 50.0, maximum: 100.0}
      healed = Health.heal(health, 75.0)
      
      assert healed.current == 100.0  # Capped at maximum
    end
    
    test "regenerates over time" do
      health = %Health{
        current: 50.0,
        maximum: 100.0,
        regeneration_rate: 10.0
      }
      
      regenerated = Health.regenerate(health, 2.0)  # 2 seconds
      assert regenerated.current == 70.0
    end
    
    test "detects death state" do
      alive = %Health{current: 1.0, maximum: 100.0}
      dead = %Health{current: 0.0, maximum: 100.0}
      
      assert Health.alive?(alive)
      assert Health.dead?(dead)
    end
  end
  
  describe "Inventory component" do
    test "adds items to inventory" do
      inventory = %Inventory{max_slots: 10}
      item = %{id: "sword", quantity: 1, weight: 5.0}
      
      {:ok, updated} = Inventory.add_item(inventory, item)
      assert map_size(updated.items) == 1
      assert updated.current_weight == 5.0
    end
    
    test "respects slot limit" do
      inventory = %Inventory{
        max_slots: 1,
        items: %{0 => %{id: "item", quantity: 1}}
      }
      
      item = %{id: "sword", quantity: 1}
      assert {:error, :no_space} = Inventory.add_item(inventory, item)
    end
    
    test "respects weight limit" do
      inventory = %Inventory{max_weight: 10.0, current_weight: 8.0}
      heavy_item = %{id: "anvil", quantity: 1, weight: 5.0}
      
      assert {:error, :too_heavy} = Inventory.add_item(inventory, heavy_item)
    end
    
    test "removes items from inventory" do
      item = %{id: "potion", quantity: 5, weight: 1.0}
      inventory = %Inventory{
        items: %{0 => item},
        current_weight: 5.0
      }
      
      {:ok, updated} = Inventory.remove_item(inventory, 0)
      assert map_size(updated.items) == 0
      assert updated.current_weight == 0.0
    end
    
    test "counts items by ID" do
      inventory = %Inventory{
        items: %{
          0 => %{id: "potion", quantity: 5},
          1 => %{id: "potion", quantity: 3},
          2 => %{id: "sword", quantity: 1}
        }
      }
      
      assert Inventory.count_item(inventory, "potion") == 8
      assert Inventory.count_item(inventory, "sword") == 1
      assert Inventory.count_item(inventory, "shield") == 0
    end
  end
  
  describe "Stats component" do
    test "creates default RPG stats" do
      stats = Stats.default()
      
      assert stats.base_stats.strength == 10.0
      assert stats.base_stats.agility == 10.0
      assert Stats.get_stat(stats, :strength) == 10.0
    end
    
    test "applies flat modifiers" do
      stats = Stats.default()
      modifier = %{value: 5.0, type: :flat, source: :equipment}
      
      updated = Stats.add_modifier(stats, :strength, modifier)
      assert Stats.get_stat(updated, :strength) == 15.0
    end
    
    test "applies percentage modifiers" do
      stats = Stats.default()
      |> Stats.set_base(:strength, 100.0)
      
      modifier = %{value: 50.0, type: :percentage, source: :buff}
      updated = Stats.add_modifier(stats, :strength, modifier)
      
      assert Stats.get_stat(updated, :strength) == 150.0
    end
    
    test "applies multiplier modifiers" do
      stats = Stats.default()
      |> Stats.set_base(:strength, 10.0)
      
      modifier = %{value: 2.0, type: :multiplier, source: :buff}
      updated = Stats.add_modifier(stats, :strength, modifier)
      
      assert Stats.get_stat(updated, :strength) == 20.0
    end
    
    test "stacks modifiers correctly" do
      stats = Stats.default()
      |> Stats.set_base(:strength, 100.0)
      |> Stats.add_modifier(:strength, %{value: 10.0, type: :flat, source: :item})
      |> Stats.add_modifier(:strength, %{value: 20.0, type: :percentage, source: :buff})
      |> Stats.add_modifier(:strength, %{value: 2.0, type: :multiplier, source: :skill})
      
      # (100 + 10) * 1.2 * 2 = 264
      assert Stats.get_stat(stats, :strength) == 264.0
    end
    
    test "removes modifiers by source" do
      stats = Stats.default()
      |> Stats.add_modifier(:strength, %{value: 5.0, type: :flat, source: :buff})
      |> Stats.add_modifier(:strength, %{value: 3.0, type: :flat, source: :item})
      
      assert Stats.get_stat(stats, :strength) == 18.0
      
      updated = Stats.remove_modifiers_by_source(stats, :buff)
      assert Stats.get_stat(updated, :strength) == 13.0
    end
  end
  
  describe "NetworkID component" do
    test "generates unique IDs" do
      id1 = NetworkID.generate()
      id2 = NetworkID.generate()
      
      assert id1 != id2
      assert String.starts_with?(id1, "net_")
    end
    
    test "creates network ID with owner" do
      network_id = NetworkID.new("player_123")
      
      assert network_id.owner_id == "player_123"
      assert network_id.authority == :client
      assert network_id.last_sync != nil
    end
    
    test "validates network ID" do
      valid = %NetworkID{id: "net_123", authority: :server}
      assert :ok = NetworkID.validate(valid)
      
      invalid = %NetworkID{id: "", authority: :server}
      assert {:error, _} = NetworkID.validate(invalid)
    end
    
    test "tracks sync timing" do
      network_id = NetworkID.new()
      
      # Sleep to ensure time difference
      Process.sleep(10)
      
      # Should need sync with small threshold
      assert NetworkID.needs_sync?(network_id, 5)
      
      # Mark as synced
      synced = NetworkID.mark_synced(network_id)
      refute NetworkID.needs_sync?(synced, 1000)
    end
  end
end