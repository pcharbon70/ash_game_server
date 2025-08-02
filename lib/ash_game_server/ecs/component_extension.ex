defmodule AshGameServer.ECS.ComponentExtension do
  @moduledoc """
  Spark DSL extension for defining ECS components.
  
  Components are pure data containers that can be attached to entities.
  They define the attributes and constraints for game data.
  """
  
  # Define component section and entities
  defp component_sections do
    [
      %Spark.Dsl.Section{
        name: :components,
        describe: """
        Define components for the ECS system.
        
        Components are pure data structures that can be attached to entities.
        They should contain no logic, only data and validation rules.
        """,
        examples: [
          """
          components do
            component :position do
              attribute :x, :float, default: 0.0
              attribute :y, :float, default: 0.0
            end
            
            component :velocity do
              attribute :dx, :float, default: 0.0
              attribute :dy, :float, default: 0.0
            end
          end
          """
        ],
        entities: [component_entity()],
        schema: [
          storage_backend: [
            type: {:in, [:ets, :persistent]},
            default: :ets,
            doc: "Default storage backend for all components"
          ]
        ]
      }
    ]
  end
  
  defp component_entity do
    %Spark.Dsl.Entity{
      name: :component,
      describe: """
      Defines a component with its attributes and constraints.
      
      Components are the data containers in the ECS pattern. They should
      contain only data, no behavior.
      """,
      examples: [
        """
        component :position do
          attribute :x, :float, default: 0.0
          attribute :y, :float, default: 0.0
          attribute :z, :float, default: 0.0
        end
        """,
        """
        component :health do
          attribute :current, :integer, default: 100
          attribute :max, :integer, default: 100
          
          validate :current_not_greater_than_max
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
        storage: [
          type: {:in, [:ets, :persistent, :memory]},
          default: :ets,
          doc: "Storage backend for this component"
        ],
        indexed: [
          type: {:list, :atom},
          default: [],
          doc: "List of attributes to index for fast queries"
        ]
      ],
      entities: [
        attributes: [attribute_entity()],
        validations: [validation_entity()]
      ]
    }
  end
  
  defp attribute_entity do
    %Spark.Dsl.Entity{
      name: :attribute,
      describe: "Defines an attribute of a component",
      examples: [
        "attribute :x, :float, default: 0.0",
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
          type: {:in, [:integer, :float, :string, :boolean, :atom, :map, :list, :uuid, :datetime]},
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
          doc: "Additional constraints for the attribute"
        ]
      ]
    }
  end
  
  defp validation_entity do
    %Spark.Dsl.Entity{
      name: :validate,
      describe: "Adds a validation rule to the component",
      examples: [
        "validate :positive_health, message: \"Health must be positive\""
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
          doc: "Error message when validation fails"
        ],
        check: [
          type: {:spark_function_behaviour, AshGameServer.ECS.Component.Check, {AshGameServer.ECS.Component.Check, 1}},
          doc: "Function to perform the validation"
        ]
      ]
    }
  end
  
  use Spark.Dsl.Extension
  
  @impl true
  def sections, do: component_sections()
  
  @impl true
  def transformers do
    [AshGameServer.ECS.Transformers.ValidateComponents]
  end
  
  @doc """
  Get all defined components for a module.
  """
  def components(module) do
    Spark.Dsl.Extension.get_entities(module, [:components])
  end
  
  @doc """
  Get a specific component by name.
  """
  def get_component(module, name) do
    module
    |> components()
    |> Enum.find(&(&1.name == name))
  end
  
  @doc """
  Get the storage backend for components.
  """
  def storage_backend(module) do
    Spark.Dsl.Extension.get_opt(module, [:components], :storage_backend, :ets)
  end
end