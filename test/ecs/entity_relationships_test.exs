defmodule AshGameServer.ECS.EntityRelationshipsTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.ECS.Entity
  alias AshGameServer.ECS.EntityRegistry  
  alias AshGameServer.ECS.EntityRelationships
  
  setup do
    # Start required services for testing
    start_supervised!({EntityRegistry, []})
    start_supervised!({EntityRelationships, []})
    
    # Create some test entities
    {:ok, parent} = Entity.create(archetype: :player, tags: [:parent])
    {:ok, child1} = Entity.create(archetype: :npc, tags: [:child])
    {:ok, child2} = Entity.create(archetype: :npc, tags: [:child])
    {:ok, standalone} = Entity.create(archetype: :item, tags: [:standalone])
    
    %{
      parent_id: parent.id,
      child1_id: child1.id,
      child2_id: child2.id,
      standalone_id: standalone.id
    }
  end
  
  describe "parent-child relationships" do
    test "adds child to parent", %{parent_id: parent_id, child1_id: child1_id} do
      :ok = EntityRelationships.add_child(parent_id, child1_id)
      
      children = EntityRelationships.get_children(parent_id)
      parent = EntityRelationships.get_parent(child1_id)
      
      assert child1_id in children
      assert parent == parent_id
    end
    
    test "removes child from parent", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      
      :ok = EntityRelationships.remove_child(parent_id, child1_id)
      
      children = EntityRelationships.get_children(parent_id)
      parent = EntityRelationships.get_parent(child1_id)
      
      refute child1_id in children
      assert parent == nil
    end
    
    test "gets all descendants recursively", %{parent_id: parent_id, child1_id: child1_id, child2_id: child2_id} do
      # Create grandchild
      {:ok, grandchild} = Entity.create(archetype: :item)
      grandchild_id = grandchild.id
      
      EntityRelationships.add_child(parent_id, child1_id)
      EntityRelationships.add_child(child1_id, grandchild_id)
      
      descendants = EntityRelationships.get_descendants(parent_id)
      
      assert child1_id in descendants
      assert grandchild_id in descendants
      assert length(descendants) == 2
    end
    
    test "gets all ancestors recursively", %{parent_id: parent_id, child1_id: child1_id} do
      # Create grandparent
      {:ok, grandparent} = Entity.create(archetype: :player)
      grandparent_id = grandparent.id
      
      EntityRelationships.add_child(grandparent_id, parent_id)
      EntityRelationships.add_child(parent_id, child1_id)
      
      ancestors = EntityRelationships.get_ancestors(child1_id)
      
      assert parent_id in ancestors
      assert grandparent_id in ancestors
      assert length(ancestors) == 2
    end
    
    test "calculates hierarchy levels", %{parent_id: parent_id, child1_id: child1_id} do
      {:ok, grandchild} = Entity.create(archetype: :item)
      grandchild_id = grandchild.id
      
      EntityRelationships.add_child(parent_id, child1_id)
      EntityRelationships.add_child(child1_id, grandchild_id)
      
      assert EntityRelationships.get_hierarchy_level(parent_id) == 0
      assert EntityRelationships.get_hierarchy_level(child1_id) == 1
      assert EntityRelationships.get_hierarchy_level(grandchild_id) == 2
    end
    
    test "checks ancestor relationships", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      
      assert EntityRelationships.ancestor?(parent_id, child1_id)
      refute EntityRelationships.ancestor?(child1_id, parent_id)
    end
    
    test "checks descendant relationships", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      
      assert EntityRelationships.descendant?(child1_id, parent_id)
      refute EntityRelationships.descendant?(parent_id, child1_id)
    end
    
    test "prevents self-parenting", %{parent_id: parent_id} do
      {:error, :cannot_parent_self} = EntityRelationships.add_child(parent_id, parent_id)
    end
    
    test "prevents circular relationships", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      
      # Trying to make parent a child of its own child should fail
      {:error, :would_create_cycle} = EntityRelationships.add_child(child1_id, parent_id)
    end
  end
  
  describe "navigation utilities" do
    test "finds root entity", %{parent_id: parent_id, child1_id: child1_id} do
      {:ok, grandchild} = Entity.create(archetype: :item)
      grandchild_id = grandchild.id
      
      EntityRelationships.add_child(parent_id, child1_id)
      EntityRelationships.add_child(child1_id, grandchild_id)
      
      assert EntityRelationships.find_root(grandchild_id) == parent_id
      assert EntityRelationships.find_root(child1_id) == parent_id
      assert EntityRelationships.find_root(parent_id) == parent_id
    end
    
    test "gets siblings", %{parent_id: parent_id, child1_id: child1_id, child2_id: child2_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      EntityRelationships.add_child(parent_id, child2_id)
      
      siblings_of_child1 = EntityRelationships.get_siblings(child1_id)
      siblings_of_child2 = EntityRelationships.get_siblings(child2_id)
      
      assert child2_id in siblings_of_child1
      assert child1_id in siblings_of_child2
      refute child1_id in siblings_of_child1  # Should not include self
    end
    
    test "gets entities at specific hierarchy level", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      
      level_0_entities = EntityRelationships.get_entities_at_level(0)
      level_1_entities = EntityRelationships.get_entities_at_level(1)
      
      assert parent_id in level_0_entities
      assert child1_id in level_1_entities
    end
  end
  
  describe "entity groups" do
    test "creates a new group" do
      {:ok, group} = EntityRelationships.create_group(:test_group, "Test Group")
      
      assert group.id == :test_group
      assert group.name == "Test Group"
      assert group.members == []
    end
    
    test "creates group with options" do
      opts = [
        description: "A group for testing",
        owner: 123,
        group_type: :party,
        metadata: %{max_size: 4}
      ]
      
      {:ok, group} = EntityRelationships.create_group(:party_group, "Party", opts)
      
      assert group.description == "A group for testing"
      assert group.owner == 123
      assert group.group_type == :party
      assert group.metadata.max_size == 4
    end
    
    test "adds entity to group", %{child1_id: child1_id} do
      EntityRelationships.create_group(:test_group, "Test Group")
      
      :ok = EntityRelationships.add_to_group(child1_id, :test_group)
      
      members = EntityRelationships.get_group_members(:test_group)
      groups = EntityRelationships.get_entity_groups(child1_id)
      
      assert child1_id in members
      assert :test_group in groups
    end
    
    test "removes entity from group", %{child1_id: child1_id} do
      EntityRelationships.create_group(:test_group, "Test Group")
      EntityRelationships.add_to_group(child1_id, :test_group)
      
      :ok = EntityRelationships.remove_from_group(child1_id, :test_group)
      
      members = EntityRelationships.get_group_members(:test_group)
      groups = EntityRelationships.get_entity_groups(child1_id)
      
      refute child1_id in members
      refute :test_group in groups
    end
    
    test "deletes group and cleans up memberships", %{child1_id: child1_id, child2_id: child2_id} do
      EntityRelationships.create_group(:delete_group, "Delete Me")
      EntityRelationships.add_to_group(child1_id, :delete_group)
      EntityRelationships.add_to_group(child2_id, :delete_group)
      
      :ok = EntityRelationships.delete_group(:delete_group)
      
      {:error, :not_found} = EntityRelationships.get_group(:delete_group)
      
      # Memberships should be cleaned up
      groups1 = EntityRelationships.get_entity_groups(child1_id)
      groups2 = EntityRelationships.get_entity_groups(child2_id)
      
      refute :delete_group in groups1
      refute :delete_group in groups2
    end
    
    test "updates group metadata" do
      EntityRelationships.create_group(:update_group, "Update Me")
      
      updates = %{
        name: "Updated Name",
        description: "Updated description",
        metadata: %{version: 2}
      }
      
      :ok = EntityRelationships.update_group(:update_group, updates)
      
      {:ok, group} = EntityRelationships.get_group(:update_group)
      assert group.name == "Updated Name"
      assert group.description == "Updated description"
      assert group.metadata.version == 2
    end
    
    test "lists all groups" do
      EntityRelationships.create_group(:group1, "Group 1")
      EntityRelationships.create_group(:group2, "Group 2")
      
      groups = EntityRelationships.list_groups()
      
      group_ids = Enum.map(groups, & &1.id)
      assert :group1 in group_ids
      assert :group2 in group_ids
    end
    
    test "prevents adding entity to non-existent group", %{child1_id: child1_id} do
      {:error, :group_not_found} = EntityRelationships.add_to_group(child1_id, :nonexistent)
    end
    
    test "prevents adding non-existent entity to group" do
      EntityRelationships.create_group(:test_group, "Test")
      
      {:error, :entity_not_found} = EntityRelationships.add_to_group(99_999, :test_group)
    end
  end
  
  describe "generic relationships" do
    test "creates custom relationship", %{parent_id: parent_id, child1_id: child1_id} do
      metadata = %{strength: :strong, description: "Allies"}
      
      :ok = EntityRelationships.create_relationship(parent_id, child1_id, :linked, metadata)
      
      relationships = EntityRelationships.get_relationships(parent_id)
      
      assert length(relationships) > 0
      
      linked_rels = EntityRelationships.get_relationships_by_type(parent_id, :linked)
      assert length(linked_rels) > 0
    end
    
    test "removes relationship", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.create_relationship(parent_id, child1_id, :linked)
      
      EntityRelationships.remove_relationship(parent_id, child1_id, :linked)
      
      refute EntityRelationships.has_relationship?(parent_id, child1_id, :linked)
    end
    
    test "checks for specific relationship", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.create_relationship(parent_id, child1_id, :linked)
      
      assert EntityRelationships.has_relationship?(parent_id, child1_id, :linked)
      refute EntityRelationships.has_relationship?(parent_id, child1_id, :enemy)
    end
    
    test "gets relationships by type", %{parent_id: parent_id, child1_id: child1_id, child2_id: child2_id} do
      EntityRelationships.create_relationship(parent_id, child1_id, :linked)
      EntityRelationships.create_relationship(parent_id, child2_id, :linked)
      EntityRelationships.create_relationship(parent_id, child2_id, :enemy)
      
      linked_relationships = EntityRelationships.get_relationships_by_type(parent_id, :linked)
      enemy_relationships = EntityRelationships.get_relationships_by_type(parent_id, :enemy)
      
      assert length(linked_relationships) == 2
      assert length(enemy_relationships) == 1
    end
  end
  
  describe "cascade operations" do
    test "cascades entity destruction", %{parent_id: parent_id, child1_id: child1_id} do
      # Set up relationships
      EntityRelationships.add_child(parent_id, child1_id)
      EntityRelationships.create_group(:test_group, "Test")
      EntityRelationships.add_to_group(child1_id, :test_group)
      EntityRelationships.create_relationship(parent_id, child1_id, :linked)
      
      # Perform cascade destroy
      :ok = EntityRelationships.cascade_destroy(child1_id)
      
      # Verify cleanup
      groups = EntityRelationships.get_entity_groups(child1_id)
      relationships = EntityRelationships.get_relationships(child1_id)
      
      assert groups == []
      assert relationships == []
    end
  end
  
  describe "statistics and monitoring" do
    test "gets relationship statistics", %{parent_id: parent_id, child1_id: child1_id} do
      EntityRelationships.add_child(parent_id, child1_id)
      EntityRelationships.create_group(:stats_group, "Stats")
      EntityRelationships.create_relationship(parent_id, child1_id, :linked)
      
      stats = EntityRelationships.get_relationship_stats()
      
      assert Map.has_key?(stats, :total_relationships)
      assert Map.has_key?(stats, :total_groups)
      assert Map.has_key?(stats, :hierarchy_cache_size)
      assert is_integer(stats.total_relationships)
    end
  end
  
  describe "error handling" do
    test "handles non-existent entities gracefully" do
      assert EntityRelationships.get_children(99_999) == []
      assert EntityRelationships.get_parent(99_999) == nil
      assert EntityRelationships.get_siblings(99_999) == []
    end
    
    test "handles group operations on non-existent groups" do
      {:error, :group_not_found} = EntityRelationships.delete_group(:nonexistent)
      {:error, :not_found} = EntityRelationships.get_group(:nonexistent)
      assert EntityRelationships.get_group_members(:nonexistent) == []
    end
  end
end