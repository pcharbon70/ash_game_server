defmodule AshGameServer.ECS.Component do
  @moduledoc """
  Struct representing an ECS component definition.
  """
  
  defstruct [
    :name,
    :description,
    :storage,
    :indexed,
    attributes: [],
    validations: []
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    description: String.t() | nil,
    storage: :ets | :persistent | :memory,
    indexed: list(atom()),
    attributes: list(AshGameServer.ECS.Component.Attribute.t()),
    validations: list(AshGameServer.ECS.Component.Validation.t())
  }
end

defmodule AshGameServer.ECS.Component.Attribute do
  @moduledoc """
  Struct representing a component attribute.
  """
  
  defstruct [
    :name,
    :type,
    :default,
    :required,
    :constraints
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    type: atom(),
    default: any(),
    required: boolean(),
    constraints: keyword()
  }
end

defmodule AshGameServer.ECS.Component.Validation do
  @moduledoc """
  Struct representing a component validation rule.
  """
  
  defstruct [
    :name,
    :message,
    :check
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    message: String.t() | nil,
    check: function() | nil
  }
end

defmodule AshGameServer.ECS.Component.Check do
  @moduledoc """
  Behavior for component validation checks.
  """
  
  @callback validate(component_data :: map()) :: :ok | {:error, String.t()}
end