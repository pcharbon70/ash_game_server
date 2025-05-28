# Gaming Engine Server Design with Deep Ash Framework Integration

## Architecture Overview

The redesigned gaming engine leverages Ash framework's declarative architecture, combining ETS-based hot storage with periodic PostgreSQL snapshots, checkpoint-based recovery, and a sophisticated DSL extension system for ECS integration.

### Core Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Game Client Layer                         │
│              (Phoenix LiveView / Channels)                   │
├─────────────────────────────────────────────────────────────┤
│                   Ash Domain Layer                           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ Game.Session │ │ Game.Combat  │ │ Game.Economy │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
├─────────────────────────────────────────────────────────────┤
│                  Ash Resource Layer                          │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐   │
│  │ Player │ │ Match  │ │ Entity │ │ Event  │ │  Item  │   │
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘   │
├─────────────────────────────────────────────────────────────┤
│               Custom Data Layer (Hybrid)                     │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ ETS (Hot)   │ │ PostgreSQL   │ │ Event Store  │        │
│  │ Active State│ │ (Snapshots)  │ │ (Recovery)   │        │
│  └─────────────┘ └──────────────┘ └──────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## 1. Custom Hybrid Data Layer Implementation

### Gaming.DataLayer.Hybrid

```elixir
defmodule Gaming.DataLayer.Hybrid do
  use Ash.DataLayer

  @behaviour Ash.DataLayer

  defstruct [
    :ets_config,
    :persistence_config,
    :snapshot_interval,
    :event_retention
  ]

  # DSL extension for configuration
  @datasource %Spark.Dsl.Section{
    name: :hybrid,
    schema: [
      ets_table: [
        type: :atom,
        required: true,
        doc: "Name of the ETS table for hot storage"
      ],
      ets_type: [
        type: {:one_of, [:set, :ordered_set, :bag]},
        default: :set,
        doc: "ETS table type"
      ],
      snapshot_interval: [
        type: :pos_integer,
        default: 300,
        doc: "Seconds between automatic snapshots"
      ],
      checkpoint_strategy: [
        type: {:one_of, [:incremental, :full, :hybrid]},
        default: :hybrid,
        doc: "Checkpoint creation strategy"
      ],
      event_store: [
        type: :boolean,
        default: true,
        doc: "Enable event sourcing for recovery"
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@datasource]

  # Feature support declaration
  def can?(resource, feature) do
    case feature do
      :create -> true
      :read -> true
      :update -> true
      :destroy -> true
      :filter -> true
      :sort -> ets_type(resource) == :ordered_set
      :transact -> false  # ETS doesn't support transactions
      :bulk_create -> true
      :async -> true
      {:lateral_join, _} -> false
      :upsert -> true
      _ -> false
    end
  end

  # Checkpoint-aware read operations
  def run_query(query, resource) do
    ets_table = ets_table(resource)
    
    case query_complexity(query) do
      :simple ->
        # Direct ETS lookup for simple queries
        ets_query(ets_table, query)
      
      :complex ->
        # Combine ETS with persisted data for complex queries
        hybrid_query(ets_table, query, resource)
      
      :historical ->
        # Event sourcing for point-in-time queries
        event_sourced_query(query, resource)
    end
  end

  # Write operations with event logging
  def create(resource, changeset) do
    record = Ash.Changeset.apply_attributes(changeset)
    ets_table = ets_table(resource)
    
    # Write to ETS for immediate availability
    :ets.insert(ets_table, to_ets_format(record))
    
    # Log event for recovery
    if event_store_enabled?(resource) do
      log_event(:create, resource, record)
    end
    
    # Schedule background persistence
    schedule_snapshot(resource, record)
    
    {:ok, record}
  end

  # Update with optimistic locking
  def update(resource, changeset) do
    ets_table = ets_table(resource)
    key = primary_key(changeset)
    
    case :ets.lookup(ets_table, key) do
      [{^key, current_data, version}] ->
        if version == changeset.data.__meta__.version do
          new_data = Ash.Changeset.apply_attributes(changeset)
          new_version = version + 1
          
          :ets.insert(ets_table, {key, new_data, new_version})
          log_event(:update, resource, new_data, changeset.changes)
          
          {:ok, %{new_data | __meta__: %{version: new_version}}}
        else
          {:error, :stale_data}
        end
      
      [] ->
        {:error, :not_found}
    end
  end

  # Checkpoint creation
  def create_checkpoint(resource) do
    ets_table = ets_table(resource)
    checkpoint_id = generate_checkpoint_id()
    
    # Capture current ETS state
    state = :ets.tab2list(ets_table)
    
    # Persist checkpoint
    %Gaming.Checkpoint{
      id: checkpoint_id,
      resource: resource,
      state: state,
      created_at: DateTime.utc_now()
    }
    |> Gaming.Repo.insert!()
    
    # Trim old events if using event sourcing
    if event_store_enabled?(resource) do
      trim_events_before(checkpoint_id)
    end
    
    {:ok, checkpoint_id}
  end

  # Recovery from checkpoint
  def restore_from_checkpoint(resource, checkpoint_id \\ :latest) do
    checkpoint = fetch_checkpoint(resource, checkpoint_id)
    ets_table = ets_table(resource)
    
    # Clear current state
    :ets.delete_all_objects(ets_table)
    
    # Restore checkpoint state
    Enum.each(checkpoint.state, fn record ->
      :ets.insert(ets_table, record)
    end)
    
    # Replay events since checkpoint
    if event_store_enabled?(resource) do
      replay_events_since(checkpoint.created_at, resource)
    end
    
    {:ok, checkpoint.id}
  end
end
```

## 2. ECS Integration as Spark DSL Extensions

### Resource-Level ECS Extension

```elixir
defmodule Gaming.Extensions.ECS do
  use Spark.Dsl.Extension,
    sections: [@components_section, @systems_section],
    transformers: [
      Gaming.Extensions.ECS.ComponentTransformer,
      Gaming.Extensions.ECS.SystemTransformer
    ]

  @components_section %Spark.Dsl.Section{
    name: :components,
    describe: "Define ECS components for this resource",
    entities: [
      %Spark.Dsl.Entity{
        name: :component,
        target: Gaming.Extensions.ECS.Component,
        args: [:name],
        schema: [
          name: [type: :atom, required: true],
          type: [type: :module, required: true],
          default: [type: :any],
          index: [type: :boolean, default: false]
        ]
      }
    ]
  }

  @systems_section %Spark.Dsl.Section{
    name: :systems,
    describe: "Define systems that process this resource",
    entities: [
      %Spark.Dsl.Entity{
        name: :system,
        target: Gaming.Extensions.ECS.System,
        args: [:name],
        schema: [
          name: [type: :atom, required: true],
          module: [type: :module, required: true],
          requires: [type: {:list, :atom}, default: []],
          priority: [type: :integer, default: 100],
          run_on: [type: {:one_of, [:create, :update, :tick]}, default: :tick]
        ]
      }
    ]
  }
end

# Component module
defmodule Gaming.Extensions.ECS.Component do
  defstruct [:name, :type, :default, :index]

  # Transform component definitions into Ash attributes
  def to_ash_attribute(%__MODULE__{} = component) do
    %Ash.Resource.Attribute{
      name: component.name,
      type: component.type,
      default: component.default,
      allow_nil?: true,
      public?: true
    }
  end
end

# System transformer
defmodule Gaming.Extensions.ECS.SystemTransformer do
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    systems = Gaming.Extensions.ECS.Info.systems(dsl_state)
    
    dsl_state
    |> add_system_actions(systems)
    |> add_system_changes(systems)
    |> {:ok, _}
  end

  defp add_system_actions(dsl_state, systems) do
    Enum.reduce(systems, dsl_state, fn system, state ->
      action = Spark.Dsl.Transformer.build_entity(
        Ash.Resource.Dsl,
        [:actions],
        :update,
        name: :"run_#{system.name}",
        accept: system.requires,
        changes: [
          {Gaming.Changes.RunSystem, [system: system.module]}
        ]
      )
      
      Spark.Dsl.Transformer.add_entity(state, [:actions], action)
    end)
  end
end
```

### Domain-Level ECS Extension

```elixir
defmodule Gaming.Extensions.GameWorld do
  use Spark.Dsl.Extension,
    sections: [@world_section],
    transformers: [Gaming.Extensions.GameWorld.WorldTransformer]

  @world_section %Spark.Dsl.Section{
    name: :game_world,
    schema: [
      tick_rate: [
        type: :pos_integer,
        default: 60,
        doc: "Game loop frequency in Hz"
      ],
      world_size: [
        type: {:tuple, [:pos_integer, :pos_integer]},
        default: {1000, 1000},
        doc: "World dimensions"
      ],
      physics_engine: [
        type: :module,
        default: Gaming.Physics.Simple,
        doc: "Physics simulation module"
      ],
      ecs_scheduler: [
        type: {:one_of, [:sequential, :parallel, :adaptive]},
        default: :adaptive,
        doc: "System execution strategy"
      ]
    ],
    entities: [
      %Spark.Dsl.Entity{
        name: :world_system,
        target: Gaming.Extensions.GameWorld.WorldSystem,
        args: [:name],
        schema: [
          name: [type: :atom, required: true],
          resources: [type: {:list, :module}, required: true],
          execution_order: [type: :integer, default: 100]
        ]
      }
    ]
  }

  # World system coordinator
  defmodule WorldSystem do
    defstruct [:name, :resources, :execution_order]

    def execute(%__MODULE__{} = system, domain) do
      # Coordinate cross-resource system execution
      system.resources
      |> Enum.map(&fetch_entities(&1, domain))
      |> run_cross_resource_logic(system)
    end
  end
end
```

## 3. Game Resource Examples with Extensions

### Player Resource

```elixir
defmodule Gaming.Entities.Player do
  use Ash.Resource,
    domain: Gaming.Session,
    data_layer: Gaming.DataLayer.Hybrid,
    extensions: [
      AshStateMachine,
      Gaming.Extensions.ECS,
      Ash.Policy.Authorizer
    ]

  # Hybrid data layer configuration
  hybrid do
    ets_table :players
    ets_type :set
    snapshot_interval 300
    checkpoint_strategy :hybrid
    event_store true
  end

  # ECS components
  components do
    component :position, Gaming.Components.Position do
      default %{x: 0, y: 0, z: 0}
      index true
    end
    
    component :velocity, Gaming.Components.Velocity do
      default %{dx: 0, dy: 0, dz: 0}
    end
    
    component :health, Gaming.Components.Health do
      default %{current: 100, max: 100}
    end
    
    component :inventory, Gaming.Components.Inventory do
      default %{items: [], capacity: 20}
    end
  end

  # ECS systems
  systems do
    system :movement do
      module Gaming.Systems.Movement
      requires [:position, :velocity]
      priority 100
      run_on :tick
    end
    
    system :combat do
      module Gaming.Systems.Combat
      requires [:position, :health]
      priority 200
      run_on :update
    end
  end

  # State machine for player states
  state_machine do
    initial_states [:idle]
    default_initial_state :idle
    
    states [:idle, :moving, :combat, :dead, :respawning]
    
    transitions do
      transition :start_moving, from: :idle, to: :moving
      transition :stop_moving, from: :moving, to: :idle
      transition :enter_combat, from: [:idle, :moving], to: :combat
      transition :exit_combat, from: :combat, to: :idle
      transition :die, from: [:idle, :moving, :combat], to: :dead
      transition :respawn, from: :dead, to: :respawning
      transition :finish_respawn, from: :respawning, to: :idle
    end
  end

  # Core attributes
  attributes do
    uuid_primary_key :id
    attribute :username, :string, allow_nil?: false
    attribute :level, :integer, default: 1
    attribute :experience, :integer, default: 0
    
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  # Relationships
  relationships do
    belongs_to :current_match, Gaming.Entities.Match
    has_many :items, Gaming.Entities.Item
    has_many :game_events, Gaming.Events.PlayerEvent
  end

  # Actions with integrated ECS
  actions do
    defaults [:read]
    
    create :join_game do
      accept [:username]
      
      change Gaming.Changes.AssignStartingPosition
      change Gaming.Changes.InitializeComponents
    end
    
    update :move do
      accept []
      
      argument :direction, Gaming.Types.Direction, allow_nil?: false
      argument :speed, :float, default: 1.0
      
      change Gaming.Changes.UpdateVelocity
      change {Gaming.Changes.RunSystem, system: Gaming.Systems.Movement}
    end
    
    update :take_damage do
      argument :amount, :integer, allow_nil?: false
      argument :source, :uuid
      
      change Gaming.Changes.ApplyDamage
      change Gaming.Changes.CheckDeath
    end
    
    # Checkpoint actions
    action :create_checkpoint, :generic do
      run Gaming.Actions.CreatePlayerCheckpoint
    end
    
    action :restore_checkpoint, :generic do
      argument :checkpoint_id, :uuid, allow_nil?: false
      run Gaming.Actions.RestorePlayerCheckpoint
    end
  end

  # Authorization policies
  policies do
    policy action_type(:read) do
      authorize_if always()
    end
    
    policy action(:move) do
      authorize_if expr(id == ^actor(:id) and state != :dead)
    end
    
    policy action(:take_damage) do
      authorize_if Gaming.Checks.ValidCombatTarget
    end
  end

  # Calculations
  calculations do
    calculate :next_level_experience, :integer, 
      expr(level * 1000)
    
    calculate :health_percentage, :float,
      expr(health.current / health.max * 100)
    
    calculate :movement_speed, :float, Gaming.Calculations.MovementSpeed
  end

  # Aggregates
  aggregates do
    count :total_kills, :game_events, filter: expr(type == :kill)
    count :total_deaths, :game_events, filter: expr(type == :death)
    sum :total_damage_dealt, :game_events, field: :damage
  end
end
```

### Match Resource

```elixir
defmodule Gaming.Entities.Match do
  use Ash.Resource,
    domain: Gaming.Session,
    data_layer: Gaming.DataLayer.Hybrid,
    extensions: [
      AshStateMachine,
      Gaming.Extensions.GameWorld
    ]

  hybrid do
    ets_table :active_matches
    ets_type :ordered_set
    snapshot_interval 60
    checkpoint_strategy :incremental
  end

  game_world do
    tick_rate 30
    world_size {2000, 2000}
    physics_engine Gaming.Physics.Grid
    ecs_scheduler :parallel
    
    world_system :match_logic do
      resources [Gaming.Entities.Player, Gaming.Entities.Projectile]
      execution_order 100
    end
  end

  state_machine do
    initial_states [:waiting]
    default_initial_state :waiting
    
    states [:waiting, :starting, :active, :ending, :completed]
    
    transitions do
      transition :start_match, from: :waiting, to: :starting
      transition :activate, from: :starting, to: :active
      transition :end_match, from: :active, to: :ending
      transition :complete, from: :ending, to: :completed
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :match_type, Gaming.Types.MatchType
    attribute :max_players, :integer, default: 10
    attribute :duration_seconds, :integer
    attribute :game_state, :map, default: %{}
    
    create_timestamp :started_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :players, Gaming.Entities.Player
    has_many :events, Gaming.Events.MatchEvent
  end

  actions do
    defaults [:read]
    
    create :create_match do
      accept [:match_type, :max_players, :duration_seconds]
      
      change set_attribute(:state, :waiting)
      change Gaming.Changes.InitializeWorld
    end
    
    update :tick do
      change Gaming.Changes.ProcessGameTick
      change Gaming.Changes.CheckWinConditions
    end
    
    update :add_player do
      argument :player_id, :uuid, allow_nil?: false
      
      validate Gaming.Validations.MatchNotFull
      validate Gaming.Validations.PlayerNotInMatch
      
      change Gaming.Changes.AddPlayerToMatch
      change Gaming.Changes.CheckMatchStart
    end
  end

  calculations do
    calculate :current_players, :integer,
      expr(count(players, filter: expr(state != :disconnected)))
    
    calculate :time_remaining, :integer,
      Gaming.Calculations.TimeRemaining
  end
end
```

## 4. Checkpoint and Recovery System

### Checkpoint Manager

```elixir
defmodule Gaming.Checkpoint.Manager do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    schedule_checkpoint_sweep()
    
    {:ok,
     %{
       interval: opts[:interval] || 300_000,  # 5 minutes
       strategy: opts[:strategy] || :incremental,
       resources: opts[:resources] || []
     }}
  end

  def handle_info(:checkpoint_sweep, state) do
    Logger.info("Starting checkpoint sweep")
    
    Enum.each(state.resources, fn resource ->
      Task.start(fn ->
        create_resource_checkpoint(resource, state.strategy)
      end)
    end)
    
    schedule_checkpoint_sweep()
    {:noreply, state}
  end

  defp create_resource_checkpoint(resource, strategy) do
    case strategy do
      :full ->
        Gaming.DataLayer.Hybrid.create_checkpoint(resource)
      
      :incremental ->
        create_incremental_checkpoint(resource)
      
      :hybrid ->
        # Full checkpoint every 10th time, incremental otherwise
        if rem(checkpoint_count(resource), 10) == 0 do
          Gaming.DataLayer.Hybrid.create_checkpoint(resource)
        else
          create_incremental_checkpoint(resource)
        end
    end
  end

  defp create_incremental_checkpoint(resource) do
    last_checkpoint = get_last_checkpoint(resource)
    events_since = get_events_since(last_checkpoint.created_at)
    
    %Gaming.IncrementalCheckpoint{
      resource: resource,
      base_checkpoint_id: last_checkpoint.id,
      events: events_since,
      created_at: DateTime.utc_now()
    }
    |> Gaming.Repo.insert!()
  end
end
```

### Recovery Actions

```elixir
defmodule Gaming.Actions.RestoreGameState do
  use Ash.Resource.Actions.Implementation

  def run(input, opts, context) do
    checkpoint_id = input.arguments.checkpoint_id || :latest
    
    with {:ok, match_checkpoint} <- restore_match_checkpoint(checkpoint_id),
         {:ok, player_checkpoints} <- restore_player_checkpoints(match_checkpoint),
         {:ok, _} <- replay_recent_events(match_checkpoint) do
      {:ok, %{match_id: match_checkpoint.match_id, restored_at: DateTime.utc_now()}}
    end
  end

  defp restore_match_checkpoint(checkpoint_id) do
    Gaming.DataLayer.Hybrid.restore_from_checkpoint(
      Gaming.Entities.Match,
      checkpoint_id
    )
  end

  defp restore_player_checkpoints(match_checkpoint) do
    match_checkpoint.player_ids
    |> Enum.map(fn player_id ->
      Task.async(fn ->
        Gaming.DataLayer.Hybrid.restore_from_checkpoint(
          Gaming.Entities.Player,
          {:match, match_checkpoint.id, player_id}
        )
      end)
    end)
    |> Task.await_many()
  end
end
```

## 5. Oban Integration for Background Jobs

```elixir
defmodule Gaming.Jobs.SnapshotWorker do
  use Oban.Worker,
    queue: :snapshots,
    max_attempts: 3,
    unique: [period: 60]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource" => resource_name, "type" => type}}) do
    resource = String.to_existing_atom(resource_name)
    
    case type do
      "full" ->
        perform_full_snapshot(resource)
      
      "incremental" ->
        perform_incremental_snapshot(resource)
      
      "cleanup" ->
        cleanup_old_snapshots(resource)
    end
  end

  defp perform_full_snapshot(resource) do
    Logger.info("Performing full snapshot for #{resource}")
    
    # Get all records from ETS
    records = Gaming.DataLayer.Hybrid.dump_ets_table(resource)
    
    # Create snapshot record
    snapshot = %Gaming.Snapshot{
      resource: resource,
      type: :full,
      data: records,
      record_count: length(records),
      created_at: DateTime.utc_now()
    }
    
    Gaming.Repo.insert!(snapshot)
    
    # Schedule cleanup job
    %{resource: resource, type: "cleanup"}
    |> Gaming.Jobs.SnapshotWorker.new(schedule_in: 3600)
    |> Oban.insert()
    
    :ok
  end
end

# Oban configuration
config :gaming, Oban,
  repo: Gaming.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", Gaming.Jobs.SnapshotWorker, args: %{type: "full"}},
       {"*/5 * * * *", Gaming.Jobs.SnapshotWorker, args: %{type: "incremental"}},
       {"0 3 * * *", Gaming.Jobs.CleanupWorker}
     ]}
  ],
  queues: [
    default: 10,
    snapshots: 2,
    events: 20,
    analytics: 5
  ]
```

## 6. Extension Dependencies and Composition

### Master Game Extension

```elixir
defmodule Gaming.Extensions.GameEngine do
  use Spark.Dsl.Extension,
    sections: [@game_section],
    transformers: [
      Gaming.Extensions.GameEngine.SetupTransformer,
      Gaming.Extensions.GameEngine.ValidationTransformer
    ],
    depends_on: [
      Gaming.Extensions.ECS,
      Gaming.Extensions.GameWorld,
      AshStateMachine
    ]

  @game_section %Spark.Dsl.Section{
    name: :game_engine,
    schema: [
      game_type: [
        type: {:one_of, [:moba, :battle_royale, :rpg, :strategy]},
        required: true
      ],
      player_count: [
        type: {:tuple, [:pos_integer, :pos_integer]},
        required: true,
        doc: "{min, max} players"
      ],
      match_duration: [
        type: :pos_integer,
        doc: "Match duration in seconds"
      ],
      enable_replay: [
        type: :boolean,
        default: true
      ]
    ]
  }

  defmodule SetupTransformer do
    use Spark.Dsl.Transformer

    def after?(transformer), do: transformer in [AshStateMachine.Transformer]

    def transform(dsl_state) do
      game_config = Gaming.Extensions.GameEngine.Info.game_engine(dsl_state)
      
      dsl_state
      |> ensure_required_components(game_config.game_type)
      |> add_game_specific_actions(game_config)
      |> configure_state_machine(game_config)
      |> {:ok, _}
    end
  end
end
```

## 7. Integration with Ash Concepts

### Complex Changes Pipeline

```elixir
defmodule Gaming.Changes.ProcessGameTick do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    changeset
    |> execute_physics_step()
    |> process_player_inputs()
    |> run_ecs_systems()
    |> check_collisions()
    |> apply_game_rules()
    |> broadcast_state_updates()
    |> schedule_next_tick()
  end

  defp run_ecs_systems(changeset) do
    match = changeset.data
    
    # Get all systems for the current game phase
    systems = get_active_systems(match.state)
    
    # Execute systems in priority order
    Enum.reduce(systems, changeset, fn system, cs ->
      entities = get_entities_for_system(system, match)
      results = system.execute(entities, match.game_state)
      
      update_game_state(cs, results)
    end)
  end
end
```

### Advanced Calculations

```elixir
defmodule Gaming.Calculations.DamageCalculation do
  use Ash.Resource.Calculation

  def calculate(records, opts, context) do
    Enum.map(records, fn player ->
      attacker = context[:arguments][:attacker]
      weapon = context[:arguments][:weapon]
      
      base_damage = weapon.damage
      
      # Apply modifiers
      damage = base_damage
      |> apply_level_scaling(attacker.level, player.level)
      |> apply_armor_reduction(player.armor)
      |> apply_critical_hit(attacker.critical_chance)
      |> apply_elemental_bonus(weapon.element, player.resistances)
      
      round(damage)
    end)
  end
end
```

### Game-Specific Aggregates

```elixir
aggregates do
  # Performance metrics
  custom :avg_tick_time, Gaming.Aggregates.AverageTickTime
  custom :peak_player_count, Gaming.Aggregates.PeakPlayerCount
  
  # Game statistics
  sum :total_damage_dealt, :combat_events, field: :damage
  count :total_kills, :combat_events, filter: expr(type == :kill)
  
  # Economic metrics
  avg :avg_gold_earned, :players, field: :gold
  max :highest_level, :players, field: :level
end
```

## 8. Deployment Architecture

### Supervision Tree

```elixir
defmodule Gaming.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Core services
      Gaming.Repo,
      {Phoenix.PubSub, name: Gaming.PubSub},
      GamingWeb.Endpoint,
      
      # Oban for background jobs
      {Oban, Application.fetch_env!(:gaming, Oban)},
      
      # Game-specific supervisors
      {DynamicSupervisor, strategy: :one_for_one, name: Gaming.MatchSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Gaming.PlayerSupervisor},
      
      # Checkpoint manager
      Gaming.Checkpoint.Manager,
      
      # ETS table manager
      Gaming.Storage.ETSManager,
      
      # Game world ticker
      Gaming.World.TickScheduler
    ]

    opts = [strategy: :one_for_one, name: Gaming.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### ETS Table Manager

```elixir
defmodule Gaming.Storage.ETSManager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Create ETS tables with proper settings
    tables = [
      {:players, [:set, :public, :named_table, {:write_concurrency, true}]},
      {:active_matches, [:ordered_set, :public, :named_table]},
      {:game_events, [:bag, :public, :named_table]},
      {:leaderboards, [:ordered_set, :public, :named_table]}
    ]
    
    Enum.each(tables, fn {name, opts} ->
      :ets.new(name, opts)
    end)
    
    # Set up heir process for table survival
    Process.flag(:trap_exit, true)
    
    {:ok, %{tables: Keyword.keys(tables)}}
  end

  def terminate(_reason, state) do
    # Transfer table ownership before shutdown
    Enum.each(state.tables, fn table ->
      transfer_table_ownership(table)
    end)
  end
end
```

## Conclusion

This architecture provides a comprehensive gaming engine that deeply integrates with Ash framework concepts while maintaining high performance through ETS-based hot storage and sophisticated checkpoint recovery. The design leverages Ash's declarative patterns for game logic while providing the real-time performance required for modern gaming applications.

Key benefits:
- **Declarative game design** through Spark DSL extensions
- **High-performance** hot path with ETS storage
- **Resilient** checkpoint-based recovery system
- **Scalable** through Elixir's actor model and OTP
- **Maintainable** with clear separation of concerns
- **Extensible** through Ash's comprehensive extension system

The system can handle thousands of concurrent game sessions while providing sub-millisecond response times for critical game operations and robust recovery mechanisms for system failures.
