defmodule AshGameServer.ECS.System do
  @moduledoc """
  Struct representing an ECS system definition.
  """

  defstruct [
    :name,
    :description,
    :priority,
    :run_every,
    :parallel,
    :enabled,
    queries: []
  ]

  @type t :: %__MODULE__{
    name: atom(),
    description: String.t() | nil,
    priority: integer(),
    run_every: integer() | nil,
    parallel: boolean(),
    enabled: boolean(),
    queries: list(AshGameServer.ECS.System.Query.t())
  }
end

defmodule AshGameServer.ECS.System.Query do
  @moduledoc """
  Struct representing a component query for a system.
  """

  defstruct [
    :components,
    :as,
    :optional,
    :exclude
  ]

  @type t :: %__MODULE__{
    components: list(atom()),
    as: atom() | nil,
    optional: list(atom()),
    exclude: list(atom())
  }
end
