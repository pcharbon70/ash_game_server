defmodule AshGameServer.GameCore.GameSession do
  @moduledoc """
  Game session resource representing an active game instance.
  
  This resource manages:
  - Game session lifecycle
  - Session configuration
  - Player participation
  - Game state tracking
  """
  use AshGameServer.Resource.Base,
    domain: AshGameServer.GameCore,
    table: "game_sessions",
    pub_sub_prefix: "game_sessions"

  # Game session attributes
  attributes do
    attribute :name, :string do
      allow_nil? false
      public? true
      
      constraints [
        min_length: 1,
        max_length: 100
      ]
    end
    
    attribute :status, :atom do
      allow_nil? false
      public? true
      default :waiting
      
      constraints [
        one_of: [:waiting, :starting, :active, :paused, :completed, :cancelled]
      ]
    end
    
    attribute :game_type, :atom do
      allow_nil? false
      public? true
      default :standard
      
      constraints [
        one_of: [:standard, :ranked, :practice, :tournament]
      ]
    end
    
    attribute :max_players, :integer do
      allow_nil? false
      public? true
      default 4
      
      constraints [
        min: 1,
        max: 100
      ]
    end
    
    attribute :current_players, :integer do
      allow_nil? false
      public? true
      default 0
      
      constraints [
        min: 0
      ]
    end
    
    attribute :config, :map do
      allow_nil? false
      public? true
      default %{
        time_limit: nil,
        score_limit: nil,
        map: "default",
        difficulty: "normal",
        rules: %{}
      }
    end
    
    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end
    
    attribute :ended_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end
    
    # Game state stored as JSON
    attribute :game_state, :map do
      allow_nil? false
      public? false
      default %{}
    end
    
    # Metadata for analytics
    attribute :metadata, :map do
      allow_nil? false
      public? false
      default %{}
    end
  end

  # Game session actions
  actions do
    # Define primary create action
    create :create do
      primary? true
      accept [:name, :game_type, :max_players, :config]
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
    
    # Start the game session
    update :start do
      accept []
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :active)
        |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())
      end
      
      validate attribute_equals(:status, :waiting)
      validate compare(:current_players, greater_than: 0)
    end
    
    # Pause the game session
    update :pause do
      accept []
      
      change set_attribute(:status, :paused)
      validate attribute_equals(:status, :active)
    end
    
    # Resume the game session
    update :resume do
      accept []
      
      change set_attribute(:status, :active)
      validate attribute_equals(:status, :paused)
    end
    
    # Complete the game session
    update :complete do
      argument :final_state, :map do
        allow_nil? false
      end
      
      change fn changeset, context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :completed)
        |> Ash.Changeset.force_change_attribute(:ended_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:game_state, context.arguments.final_state)
      end
      
      validate attribute_equals(:status, :active)
    end
    
    # Cancel the game session
    update :cancel do
      accept []
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :cancelled)
        |> Ash.Changeset.force_change_attribute(:ended_at, DateTime.utc_now())
      end
      
      validate attribute_in(:status, [:waiting, :active, :paused])
    end
    
    # Add a player to the session
    update :add_player do
      argument :player_id, :uuid do
        allow_nil? false
      end
      
      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :current_players)
        max = Ash.Changeset.get_attribute(changeset, :max_players)
        
        if current < max do
          Ash.Changeset.force_change_attribute(changeset, :current_players, current + 1)
        else
          Ash.Changeset.add_error(changeset, field: :current_players, message: "Session is full")
        end
      end
      
      validate attribute_in(:status, [:waiting])
    end
    
    # Remove a player from the session
    update :remove_player do
      argument :player_id, :uuid do
        allow_nil? false
      end
      
      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :current_players)
        new_count = max(0, current - 1)
        
        Ash.Changeset.force_change_attribute(changeset, :current_players, new_count)
      end
    end
    
    # Update game state
    update :update_game_state do
      argument :state_changes, :map do
        allow_nil? false
      end
      
      change fn changeset, context ->
        current_state = Ash.Changeset.get_attribute(changeset, :game_state)
        new_state = Map.merge(current_state, context.arguments.state_changes)
        
        Ash.Changeset.force_change_attribute(changeset, :game_state, new_state)
      end
      
      validate attribute_equals(:status, :active)
    end
  end

  # Validations
  validations do
    validate compare(:current_players, less_than_or_equal_to: :max_players)
    validate compare(:max_players, greater_than: 0)
  end

  # Relationships (to be expanded)
  relationships do
    # has_many :players, through: PlayerSession
    # has_many :events, GameEvent
  end

  # Calculations
  calculations do
    calculate :is_full, :boolean, expr(current_players >= max_players)
    
    calculate :is_active, :boolean, expr(status in [:active, :paused])
    
    calculate :duration_seconds, :integer, expr(
      if not is_nil(started_at) and not is_nil(ended_at) do
        fragment("EXTRACT(EPOCH FROM (? - ?))", ended_at, started_at)
      else
        nil
      end
    )
  end

  # Code interface for GameSession resource
  code_interface do
    define :create, action: :create, args: [:name]
    define :get, action: :read, get_by: [:id]
    define :list, action: :read
    define :update, action: :update
    define :delete, action: :destroy
    define :start, action: :start
    define :pause, action: :pause
    define :resume, action: :resume
    define :complete, action: :complete
    define :cancel, action: :cancel
    define :add_player, action: :add_player
    define :remove_player, action: :remove_player
    define :update_game_state, action: :update_game_state
  end
end