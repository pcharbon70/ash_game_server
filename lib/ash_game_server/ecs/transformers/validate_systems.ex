defmodule AshGameServer.ECS.Transformers.ValidateSystems do
  @moduledoc """
  Transformer that validates system definitions.

  Ensures that:
  - System names are unique
  - Query component references are valid
  - Priority values are reasonable
  - Run intervals are positive
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    systems = Transformer.get_entities(dsl_state, [:systems])
    components = Transformer.get_entities(dsl_state, [:components])

    with :ok <- validate_unique_names(systems),
         :ok <- validate_queries(systems, components),
         :ok <- validate_system_config(systems) do
      {:ok, dsl_state}
    else
      {:error, error} ->
        {:error, dsl_state, error}
    end
  end

  defp validate_unique_names(systems) do
    names = Enum.map(systems, & &1.name)

    case names -- Enum.uniq(names) do
      [] ->
        :ok

      duplicates ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate system names found: #{inspect(duplicates)}",
           path: [:systems]
         )}
    end
  end

  defp validate_queries(systems, components) do
    component_names = MapSet.new(Enum.map(components, & &1.name))

    Enum.reduce_while(systems, :ok, fn system, :ok ->
      case validate_system_queries(system, component_names) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_system_queries(system, component_names) do
    Enum.reduce_while(system.queries, :ok, fn query, :ok ->
      all_components = query.components ++ query.optional ++ query.exclude

      invalid_components =
        all_components
        |> Enum.reject(&MapSet.member?(component_names, &1))

      if invalid_components == [] do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message: "System #{system.name} references undefined components: #{inspect(invalid_components)}",
            path: [:systems, system.name, :queries]
          )}}
      end
    end)
  end

  defp validate_system_config(systems) do
    Enum.reduce_while(systems, :ok, fn system, :ok ->
      cond do
        system.priority < 0 or system.priority > 1000 ->
          {:halt,
           {:error,
            Spark.Error.DslError.exception(
              message: "System #{system.name} has invalid priority #{system.priority}. Must be between 0 and 1000.",
              path: [:systems, system.name]
            )}}

        system.run_every && system.run_every <= 0 ->
          {:halt,
           {:error,
            Spark.Error.DslError.exception(
              message: "System #{system.name} has invalid run_every value #{system.run_every}. Must be positive.",
              path: [:systems, system.name]
            )}}

        true ->
          {:cont, :ok}
      end
    end)
  end
end
