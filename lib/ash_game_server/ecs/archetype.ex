defmodule AshGameServer.ECS.Archetype do
  @moduledoc """
  Struct representing an entity archetype (template).
  """
  
  defstruct [
    :name,
    :description,
    :extends,
    :tags,
    components: []
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    description: String.t() | nil,
    extends: atom() | nil,
    tags: list(atom()),
    components: list(AshGameServer.ECS.Entity.ComponentRef.t())
  }
end

defmodule AshGameServer.ECS.EntityTemplate do
  @moduledoc """
  Struct representing a specific entity template.
  """
  
  defstruct [
    :name,
    :from_archetype,
    :singleton,
    components: []
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    from_archetype: atom() | nil,
    singleton: boolean(),
    components: list(AshGameServer.ECS.Entity.ComponentRef.t())
  }
end

defmodule AshGameServer.ECS.Entity.ComponentRef do
  @moduledoc """
  Struct representing a component reference in an entity or archetype.
  """
  
  defstruct [
    :name,
    :initial,
    :required
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    initial: keyword(),
    required: boolean()
  }
end