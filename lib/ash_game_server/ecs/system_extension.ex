defmodule AshGameServer.ECS.SystemExtension do
  @moduledoc """
  Spark DSL extension for defining ECS systems.
  
  Systems contain the game logic and operate on entities that have
  specific components. They define queries for components and the
  operations to perform on matching entities.
  """
  
  # Define systems section and entities
  defp system_sections do
    [
      %Spark.Dsl.Section{
        name: :systems,
        describe: """
        Define systems for the ECS architecture.
        
        Systems contain the game logic and operate on entities that match
        their component queries. They run in priority order each game tick.
        """,
        examples: [
          """
          systems do
            system :movement do
              query [:position, :velocity]
              priority 10
              
              execute do
                fn entities ->
                  Enum.each(entities, fn entity ->
                    # Update position based on velocity
                  end)
                end
              end
            end
            
            system :collision do
              query [:position, :collider]
              priority 20
              
              execute do
                fn entities ->
                  # Check for collisions
                end
              end
            end
          end
          """
        ],
        entities: [system_entity()],
        schema: [
          execution_model: [
            type: {:in, [:sequential, :parallel, :async]},
            default: :sequential,
            doc: "How systems are executed"
          ],
          tick_rate: [
            type: :integer,
            default: 60,
            doc: "Target ticks per second"
          ]
        ]
      }
    ]
  end
  
  defp system_entity do
    %Spark.Dsl.Entity{
      name: :system,
      describe: """
      Defines a system that processes entities with specific components.
      
      Systems contain the game logic and run periodically to update entity state.
      """,
      examples: [
        """
        system :movement do
          query [:position, :velocity]
          
          execute do
            fn entities ->
              Enum.map(entities, &update_position/1)
            end
          end
        end
        """,
        """
        system :combat do
          query [:health, :damage], as: :targets
          query [:attacker, :weapon], as: :attackers
          
          priority 10
          run_every 100
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
        priority: [
          type: :integer,
          default: 50,
          doc: "Execution priority (lower runs first)"
        ],
        run_every: [
          type: :integer,
          doc: "Run interval in milliseconds (nil for every tick)"
        ],
        parallel: [
          type: :boolean,
          default: false,
          doc: "Whether this system can run in parallel"
        ],
        enabled: [
          type: :boolean,
          default: true,
          doc: "Whether this system is enabled by default"
        ]
      ],
      entities: [
        queries: [query_entity()]
      ]
    }
  end
  
  defp query_entity do
    %Spark.Dsl.Entity{
      name: :query,
      describe: "Defines a component query for the system",
      examples: [
        "query [:position, :velocity]",
        "query [:health, :damage], as: :damageable"
      ],
      target: AshGameServer.ECS.System.Query,
      args: [:components],
      schema: [
        components: [
          type: {:list, :atom},
          required: true,
          doc: "List of required components"
        ],
        as: [
          type: :atom,
          doc: "Alias for this query"
        ],
        optional: [
          type: {:list, :atom},
          default: [],
          doc: "Optional components to include if present"
        ],
        exclude: [
          type: {:list, :atom},
          default: [],
          doc: "Components that must NOT be present"
        ]
      ]
    }
  end
  
  use Spark.Dsl.Extension
  
  @impl true
  def sections, do: system_sections()
  
  @impl true
  def transformers do
    [
      AshGameServer.ECS.Transformers.ValidateSystems,
      AshGameServer.ECS.Transformers.OrderSystems
    ]
  end
  
  @doc """
  Get all defined systems for a module.
  """
  def systems(module) do
    Spark.Dsl.Extension.get_entities(module, [:systems])
  end
  
  @doc """
  Get a specific system by name.
  """
  def get_system(module, name) do
    module
    |> systems()
    |> Enum.find(&(&1.name == name))
  end
  
  @doc """
  Get systems in execution order (by priority).
  """
  def ordered_systems(module) do
    module
    |> systems()
    |> Enum.sort_by(& &1.priority)
  end
  
  @doc """
  Get the execution model for systems.
  """
  def execution_model(module) do
    Spark.Dsl.Extension.get_opt(module, [:systems], :execution_model, :sequential)
  end
end