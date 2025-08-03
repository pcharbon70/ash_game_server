defmodule AshGameServer.Players.Player do
  @moduledoc """
  Player resource representing a game player.
  
  This resource tracks player information including:
  - Username and display name
  - Player status and statistics
  - Connection state
  """
  use AshGameServer.Resource.Base,
    domain: AshGameServer.Players,
    table: "players",
    pub_sub_prefix: "players"

  # Player-specific attributes
  attributes do
    attribute :username, :string do
      allow_nil? false
      public? true
      
      constraints [
        min_length: 3,
        max_length: 20,
        match: ~r/^[a-zA-Z0-9_]+$/
      ]
    end
    
    attribute :display_name, :string do
      allow_nil? false
      public? true
      default fn -> "Player" end
      
      constraints [
        min_length: 1,
        max_length: 30
      ]
    end
    
    attribute :status, :atom do
      allow_nil? false
      public? true
      default :offline
      
      constraints [
        one_of: [:online, :offline, :away, :in_game]
      ]
    end
    
    attribute :level, :integer do
      allow_nil? false
      public? true
      default 1
      
      constraints [
        min: 1,
        max: 100
      ]
    end
    
    attribute :experience_points, :integer do
      allow_nil? false
      public? true
      default 0
      
      constraints [
        min: 0
      ]
    end
    
    attribute :last_seen_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end
    
    # Game-specific stats stored as JSON
    attribute :stats, :map do
      allow_nil? false
      public? true
      default %{
        health: 100,
        mana: 50,
        stamina: 100,
        strength: 10,
        intelligence: 10,
        agility: 10
      }
    end
  end

  # Player-specific actions
  actions do
    # Define primary create action for players
    create :create do
      primary? true
      accept [:username, :display_name]
      
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end
    
    # Define primary update action
    update :update do
      primary? true
      accept :*
    end
    
    # Define primary destroy action
    destroy :destroy do
      primary? true
      soft? true
      change set_attribute(:deleted_at, &DateTime.utc_now/0)
    end
    
    # Action to update player status
    update :update_status do
      accept [:status]
      require_atomic? false
      
      change fn changeset, _context ->
        if Ash.Changeset.get_attribute(changeset, :status) == :online do
          Ash.Changeset.force_change_attribute(changeset, :last_seen_at, DateTime.utc_now())
        else
          changeset
        end
      end
    end
    
    # Action to add experience
    update :add_experience do
      require_atomic? false
      
      argument :amount, :integer do
        allow_nil? false
        constraints min: 1
      end
      
      change fn changeset, context ->
        current_exp = Ash.Changeset.get_attribute(changeset, :experience_points)
        current_level = Ash.Changeset.get_attribute(changeset, :level)
        new_exp = current_exp + context.arguments.amount
        
        # Simple level calculation (every 1000 exp = 1 level)
        new_level = min(100, div(new_exp, 1000) + 1)
        
        changeset
        |> Ash.Changeset.force_change_attribute(:experience_points, new_exp)
        |> Ash.Changeset.force_change_attribute(:level, new_level)
      end
    end
    
    # Action to update stats
    update :update_stats do
      require_atomic? false
      
      argument :stat_changes, :map do
        allow_nil? false
      end
      
      change fn changeset, context ->
        current_stats = Ash.Changeset.get_attribute(changeset, :stats)
        new_stats = Map.merge(current_stats, context.arguments.stat_changes)
        
        Ash.Changeset.force_change_attribute(changeset, :stats, new_stats)
      end
    end
  end

  # Identities for unique constraints
  identities do
    identity :unique_username, [:username]
  end

  # Validations
  validations do
    validate compare(:level, greater_than_or_equal_to: 1)
    validate compare(:experience_points, greater_than_or_equal_to: 0)
  end

  # Relationships (to be added as other resources are created)
  relationships do
    # has_many :game_sessions, AshGameServer.GameCore.PlayerSession
    # has_one :inventory, AshGameServer.Players.Inventory
  end

  # Code interface for the Player resource
  code_interface do
    define :create, action: :create, args: [:username]
    define :get, action: :read, get_by: [:id]
    define :get_by_username, action: :read, get_by: [:username]
    define :list, action: :read
    define :update, action: :update
    define :delete, action: :destroy
    define :restore, action: :restore
    define :update_status, action: :update_status
    define :add_experience, action: :add_experience
    define :update_stats, action: :update_stats
  end
end