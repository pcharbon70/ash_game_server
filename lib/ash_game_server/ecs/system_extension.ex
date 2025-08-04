defmodule AshGameServer.ECS.SystemExtension do
  @moduledoc """
  Spark DSL extension for defining ECS systems and their behaviors.

  Systems process entities with specific component combinations,
  implementing the game logic and rules.
  """

  # Define filter entity first (used by system entity)
  @filter_entity %Spark.Dsl.Entity{
    name: :filter,
    describe: "Additional filters for entity selection",
    examples: [
      "filter :health_above_zero, fn entity -> entity.health.current > 0 end",
      "filter :in_range, fn entity -> entity.position.x < 100 end"
    ],
    target: AshGameServer.ECS.System.Filter,
    args: [:name, :function],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the filter"
      ],
      function: [
        type: {:fun, 1},
        required: true,
        doc: "Filter function that returns boolean"
      ]
    ]
  }

  # Define event entity (used by system entity)
  @event_entity %Spark.Dsl.Entity{
    name: :on_event,
    describe: "Events that trigger system execution",
    examples: [
      "on_event :player_input",
      "on_event :collision_detected"
    ],
    target: AshGameServer.ECS.System.Event,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The event name"
      ],
      priority: [
        type: :integer,
        default: 0,
        doc: "Priority for handling this event"
      ]
    ]
  }

  # Define system entity
  @system_entity %Spark.Dsl.Entity{
    name: :system,
    describe: """
    Defines a system that processes entities with specific components.

    Systems contain the game logic and operate on entities that match
    their component requirements.
    """,
    examples: [
      """
      system :physics do
        requires [:position, :velocity, :mass]
        optional [:acceleration]
        run_every 16
        priority :high

        process fn entity, components ->
          # Physics calculations
          {:ok, updated_components}
        end
      end
      """,
      """
      system :ai_controller do
        requires [:position, :ai_state]
        run_when :on_event, event: :ai_tick

        process fn entity, components ->
          # AI decision making
          {:ok, %{ai_state: new_state}}
        end
      end
      """
    ],
    target: AshGameServer.ECS.System,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the system"
      ],
      description: [
        type: :string,
        doc: "Description of what this system does"
      ],
      requires: [
        type: {:list, :atom},
        default: [],
        doc: "Components that entities must have to be processed"
      ],
      optional: [
        type: {:list, :atom},
        default: [],
        doc: "Optional components that may be used if present"
      ],
      excludes: [
        type: {:list, :atom},
        default: [],
        doc: "Components that entities must NOT have"
      ],
      run_every: [
        type: :integer,
        doc: "Run interval in milliseconds"
      ],
      run_when: [
        type: {:in, [:always, :on_event, :manual]},
        default: :always,
        doc: "When the system should run"
      ],
      priority: [
        type: {:in, [:critical, :high, :medium, :low, :idle]},
        default: :medium,
        doc: "Execution priority"
      ],
      max_entities: [
        type: :integer,
        doc: "Maximum entities to process per run"
      ],
      batch_size: [
        type: :integer,
        default: 100,
        doc: "Number of entities to process in each batch"
      ],
      timeout: [
        type: :integer,
        default: 5000,
        doc: "Maximum time in ms for processing"
      ],
      enabled: [
        type: :boolean,
        default: true,
        doc: "Whether the system is enabled"
      ]
    ],
    entities: [
      filters: [@filter_entity],
      events: [@event_entity]
    ]
  }

  # Define systems section
  @system_section %Spark.Dsl.Section{
    name: :systems,
    describe: """
    Define systems that process entities with specific components.

    Systems implement the game logic by operating on entities that have
    specific component combinations. They can run on different schedules
    and have various execution priorities.
    """,
    examples: [
      """
      systems do
        system :movement do
          requires [:position, :velocity]
          run_every 16  # Run every 16ms (60 FPS)
          priority :high

          process fn entity, components ->
            # Update position based on velocity
            new_position = %{
              x: components.position.x + components.velocity.dx,
              y: components.position.y + components.velocity.dy
            }

            {:ok, %{position: new_position}}
          end
        end

        system :collision_detection do
          requires [:position, :collider]
          run_every 33  # Run every 33ms (30 FPS)
          priority :medium

          process fn entity, components ->
            # Check for collisions
            # ...implementation...
          end
        end
      end
      """
    ],
    entities: [@system_entity],
    schema: [
      parallel_execution: [
        type: :boolean,
        default: true,
        doc: "Whether systems can execute in parallel"
      ],
      max_workers: [
        type: :integer,
        doc: "Maximum number of parallel workers"
      ]
    ]
  }

  # Use Spark.Dsl.Extension with sections and transformers defined inline
  use Spark.Dsl.Extension,
    sections: [@system_section],
    transformers: [
      AshGameServer.ECS.Transformers.ValidateSystems,
      AshGameServer.ECS.Transformers.OptimizeQueries
    ]

  @doc """
  Get all defined systems for a module.
  """
  def get_systems(module) do
    Spark.Dsl.Extension.get_entities(module, [:systems])
  end

  @doc """
  Get a specific system by name.
  """
  def get_system(module, name) do
    module
    |> get_systems()
    |> Enum.find(&(&1.name == name))
  end

  @doc """
  Get systems that require a specific component.
  """
  def systems_for_component(module, component_name) do
    module
    |> get_systems()
    |> Enum.filter(fn system ->
      component_name in Map.get(system, :requires, [])
    end)
  end

  @doc """
  Check if a system is enabled.
  """
  def system_enabled?(module, name) do
    case get_system(module, name) do
      nil -> false
      system -> Map.get(system, :enabled, true)
    end
  end
end
