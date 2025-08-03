defmodule AshGameServer.ECS.EntityExtension do
  @moduledoc """
  Spark DSL extension for defining ECS entities and archetypes.
  
  Entities are containers for components. Archetypes are predefined
  entity templates that specify which components an entity should have.
  """
  
  # Define component reference entity first (used by other entities)
  @component_ref_entity %Spark.Dsl.Entity{
    name: :with_component,
    describe: "Adds a component to the entity or archetype",
    examples: [
      "with_component :position, x: 10, y: 20",
      "with_component :health, max: 200"
    ],
    target: AshGameServer.ECS.Entity.ComponentRef,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the component"
      ],
      initial: [
        type: :keyword_list,
        default: [],
        doc: "Initial values for component attributes"
      ],
      required: [
        type: :boolean,
        default: true,
        doc: "Whether this component is required"
      ]
    ]
  }
  
  # Define archetype entity
  @archetype_entity %Spark.Dsl.Entity{
    name: :archetype,
    describe: """
    Defines an entity archetype (template).
    
    Archetypes are reusable entity templates that specify a set of
    components and their initial values.
    """,
    examples: [
      """
      archetype :player do
        with_component :position
        with_component :velocity
        with_component :health, max: 100
        with_component :inventory, slots: 20
      end
      """,
      """
      archetype :enemy do
        with_component :position
        with_component :health, max: 50
        with_component :ai_controller, behavior: :aggressive
      end
      """
    ],
    target: AshGameServer.ECS.Archetype,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the archetype"
      ],
      description: [
        type: :string,
        doc: "Description of this archetype"
      ],
      extends: [
        type: :atom,
        doc: "Parent archetype to extend from"
      ],
      tags: [
        type: {:list, :atom},
        default: [],
        doc: "Tags for categorizing this archetype"
      ]
    ],
    entities: [
      components: [@component_ref_entity]
    ]
  }
  
  # Define entity template entity
  @entity_template_entity %Spark.Dsl.Entity{
    name: :entity,
    describe: """
    Defines a specific entity instance.
    
    Entities are specific game objects with predefined components
    and initial values.
    """,
    examples: [
      """
      entity :main_player do
        from_archetype :player
        with_component :name, value: "Hero"
        with_component :level, value: 1
      end
      """
    ],
    target: AshGameServer.ECS.EntityTemplate,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the entity"
      ],
      from_archetype: [
        type: :atom,
        doc: "Base archetype to use"
      ],
      singleton: [
        type: :boolean,
        default: false,
        doc: "Whether only one instance can exist"
      ]
    ],
    entities: [
      components: [@component_ref_entity]
    ]
  }
  
  # Define entities section
  @entity_section %Spark.Dsl.Section{
    name: :entities,
    describe: """
    Define entities and archetypes for the ECS system.
    
    Entities are game objects composed of components. Archetypes are
    reusable templates for creating similar entities.
    """,
    examples: [
      """
      entities do
        archetype :vehicle do
          with_component :position
          with_component :velocity
          with_component :fuel, max: 100
        end
        
        archetype :car do
          extends :vehicle
          with_component :wheels, count: 4
        end
        
        entity :player_car do
          from_archetype :car
          with_component :owner, id: nil
        end
      end
      """
    ],
    entities: [@archetype_entity, @entity_template_entity],
    schema: [
      id_generator: [
        type: {:in, [:uuid, :incremental, :custom]},
        default: :uuid,
        doc: "How entity IDs are generated"
      ],
      max_entities: [
        type: :integer,
        doc: "Maximum number of entities (nil for unlimited)"
      ]
    ]
  }
  
  # Use Spark.Dsl.Extension with sections and transformers defined inline
  use Spark.Dsl.Extension,
    sections: [@entity_section],
    transformers: [
      AshGameServer.ECS.Transformers.ValidateEntities,
      AshGameServer.ECS.Transformers.ResolveArchetypes
    ]
  
  @doc """
  Get all defined archetypes for a module.
  """
  def archetypes(module) do
    module
    |> Spark.Dsl.Extension.get_entities([:entities])
    |> Enum.filter(&(&1.__struct__ == AshGameServer.ECS.Archetype))
  end
  
  @doc """
  Get all defined entity templates for a module.
  """
  def get_entities(module) do
    module
    |> Spark.Dsl.Extension.get_entities([:entities])
    |> Enum.filter(&(&1.__struct__ == AshGameServer.ECS.EntityTemplate))
  end
  
  @doc """
  Get a specific archetype by name.
  """
  def get_archetype(module, name) do
    module
    |> archetypes()
    |> Enum.find(&(&1.name == name))
  end
  
  @doc """
  Get a specific entity template by name.
  """
  def get_entity(module, name) do
    module
    |> get_entities()
    |> Enum.find(&(&1.name == name))
  end
end