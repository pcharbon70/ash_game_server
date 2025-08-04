defmodule AshGameServer.ECS.Transformers.OrderSystems do
  @moduledoc """
  Transformer that orders systems by priority.

  Ensures systems are stored in execution order for efficient runtime processing.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    systems = Transformer.get_entities(dsl_state, [:systems])

    ordered_systems = Enum.sort_by(systems, & &1.priority)

    dsl_state =
      Enum.reduce(ordered_systems, dsl_state, fn system, state ->
        Transformer.replace_entity(state, [:systems], system, & &1.name == system.name)
      end)

    {:ok, dsl_state}
  end
end
