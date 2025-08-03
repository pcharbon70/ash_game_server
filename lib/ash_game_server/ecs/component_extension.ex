defmodule AshGameServer.ECS.ComponentExtension do
  @moduledoc """
  Spark DSL extension for defining ECS components and their attributes.
  
  Components are data containers that can be attached to entities.
  They define the structure and validation rules for game object attributes.
  """
  
  # Define attribute entity first (used by component entity)
  @attribute_entity %Spark.Dsl.Entity{
    name: :attribute,
    describe: "Defines an attribute of a component",
    examples: [
      "attribute :health, :integer, default: 100",
      "attribute :name, :string, required: true"
    ],
    target: AshGameServer.ECS.Component.Attribute,
    args: [:name, :type],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the attribute"
      ],
      type: [
        type: :any,
        required: true,
        doc: "The data type of the attribute"
      ],
      default: [
        type: :any,
        doc: "Default value for the attribute"
      ],
      required: [
        type: :boolean,
        default: false,
        doc: "Whether this attribute is required"
      ],
      constraints: [
        type: :keyword_list,
        default: [],
        doc: "Validation constraints for the attribute"
      ],
      computed: [
        type: :any,
        doc: "Function to compute the value dynamically"
      ]
    ]
  }
  
  # Define validation entity
  @validation_entity %Spark.Dsl.Entity{
    name: :validate,
    describe: "Defines a validation rule for the component",
    examples: [
      """
      validate :health_not_negative do
        validate_numericality :health, greater_than_or_equal_to: 0
      end
      """
    ],
    target: AshGameServer.ECS.Component.Validation,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the validation"
      ],
      message: [
        type: :string,
        doc: "Custom error message for validation failure"
      ],
      on: [
        type: {:list, :atom},
        default: [:create, :update],
        doc: "When to run this validation"
      ]
    ]
  }
  
  # Define component entity
  @component_entity %Spark.Dsl.Entity{
    name: :component,
    describe: """
    Defines a component that can be attached to entities.
    
    Components contain attributes that define the data structure
    and validation rules for a specific aspect of game objects.
    """,
    examples: [
      """
      component :position do
        attribute :x, :float, default: 0.0
        attribute :y, :float, default: 0.0
        
        validate :bounds_check do
          validate_numericality :x, greater_than_or_equal_to: -1000.0
          validate_numericality :x, less_than_or_equal_to: 1000.0
        end
      end
      """,
      """
      component :inventory do
        attribute :items, {:array, :map}, default: []
        attribute :capacity, :integer, default: 20
        
        validate :capacity_limit do
          validate_numericality :capacity, less_than_or_equal_to: 100
        end
      end
      """
    ],
    target: AshGameServer.ECS.Component,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the component"
      ],
      description: [
        type: :string,
        doc: "A description of what this component represents"
      ],
      table: [
        type: :atom,
        doc: "Override the ETS table name for this component"
      ],
      indexed: [
        type: {:list, :atom},
        default: [],
        doc: "List of attributes to create indexes for"
      ],
      unique: [
        type: {:list, :atom},
        default: [],
        doc: "List of attributes that must be unique across entities"
      ],
      required_components: [
        type: {:list, :atom},
        default: [],
        doc: "Other components that must exist on an entity with this component"
      ],
      persistent: [
        type: :boolean,
        default: false,
        doc: "Whether this component should be persisted to the database"
      ]
    ],
    entities: [
      attributes: [@attribute_entity],
      validations: [@validation_entity]
    ]
  }
  
  # Define the components section structure
  @component_section %Spark.Dsl.Section{
    name: :components,
    describe: """
    Define components for the ECS system.
    
    Components are data containers that can be attached to entities.
    Each component defines a specific aspect of a game object,
    such as position, health, or inventory.
    """,
    examples: [
      """
      components do
        component :position do
          attribute :x, :float, default: 0.0
          attribute :y, :float, default: 0.0
          attribute :z, :float, default: 0.0
        end
        
        component :health do
          attribute :current, :integer, default: 100
          attribute :max, :integer, default: 100
          
          validate :current_not_negative do
            validate_numericality :current, greater_than_or_equal_to: 0
          end
        end
      end
      """
    ],
    entities: [@component_entity],
    schema: [
      storage_strategy: [
        type: {:in, [:ets, :persistent, :hybrid]},
        default: :ets,
        doc: "How components are stored (ETS only, DB only, or both)"
      ]
    ]
  }
  
  # Use Spark.Dsl.Extension with sections and transformers defined inline
  use Spark.Dsl.Extension,
    sections: [@component_section],
    transformers: [
      AshGameServer.ECS.Transformers.ValidateComponents
    ]
  
  @doc """
  Get all defined components for a module.
  """
  def get_components(module) do
    Spark.Dsl.Extension.get_entities(module, [:components])
  end
  
  @doc """
  Get a specific component by name.
  """
  def get_component(module, name) do
    module
    |> get_components()
    |> Enum.find(&(&1.name == name))
  end
  
  @doc """
  Get all attributes for a component.
  """
  def component_attributes(module, component_name) do
    case get_component(module, component_name) do
      nil -> []
      component -> Map.get(component, :attributes, [])
    end
  end
  
  @doc """
  Check if a component exists.
  """
  def has_component?(module, name) do
    get_component(module, name) != nil
  end
end