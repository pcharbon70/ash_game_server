defmodule AshGameServer.ECS.ComponentBehaviour do
  @moduledoc """
  Behaviour for defining ECS components with metadata, validation, and lifecycle hooks.

  This module provides the foundation for creating robust components with:
  - Type safety and validation
  - Serialization/deserialization
  - Versioning and migration support
  - Performance monitoring
  - Event generation
  """

  @type component_data :: map()
  @type entity_id :: term()
  @type validation_result :: :ok | {:error, term()}
  @type serialized_data :: binary()
  @type component_version :: non_neg_integer()

  @doc """
  Returns the component's metadata including schema, version, and configuration.
  """
  @callback metadata() :: %{
    name: atom(),
    version: component_version(),
    schema: keyword(),
    indexes: [atom()],
    persistent: boolean(),
    validations: [atom()],
    description: String.t()
  }

  @doc """
  Validates component data before storage.
  Called on create and update operations.
  """
  @callback validate(component_data()) :: validation_result()

  @doc """
  Serializes component data for storage or transmission.
  """
  @callback serialize(component_data()) :: serialized_data()

  @doc """
  Deserializes component data from storage.
  """
  @callback deserialize(serialized_data()) :: {:ok, component_data()} | {:error, term()}

  @doc """
  Called when a component is first created on an entity.
  """
  @callback on_create(entity_id(), component_data()) :: :ok | {:error, term()}

  @doc """
  Called when a component is updated.
  """
  @callback on_update(entity_id(), component_data(), component_data()) :: :ok | {:error, term()}

  @doc """
  Called when a component is removed from an entity.
  """
  @callback on_delete(entity_id(), component_data()) :: :ok | {:error, term()}

  @doc """
  Migrates component data from an older version.
  """
  @callback migrate(component_data(), component_version(), component_version()) ::
    {:ok, component_data()} | {:error, term()}

  @optional_callbacks [
    validate: 1,
    serialize: 1,
    deserialize: 1,
    on_create: 2,
    on_update: 3,
    on_delete: 2,
    migrate: 3
  ]

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour AshGameServer.ECS.ComponentBehaviour

      @component_opts unquote(opts)
      @before_compile AshGameServer.ECS.ComponentBehaviour

      # Default implementations
      def validate(_data), do: :ok
      def serialize(data), do: :erlang.term_to_binary(data)
      def deserialize(binary), do: {:ok, :erlang.binary_to_term(binary)}
      def on_create(_entity_id, _data), do: :ok
      def on_update(_entity_id, _old_data, _new_data), do: :ok
      def on_delete(_entity_id, _data), do: :ok
      def migrate(data, _from_version, _to_version), do: {:ok, data}

      defoverridable [
        validate: 1,
        serialize: 1,
        deserialize: 1,
        on_create: 2,
        on_update: 3,
        on_delete: 2,
        migrate: 3
      ]
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def metadata do
        opts = @component_opts || []

        %{
          name: __MODULE__ |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom(),
          version: Keyword.get(opts, :version, 1),
          schema: Keyword.get(opts, :schema, []),
          indexes: Keyword.get(opts, :indexes, []),
          persistent: Keyword.get(opts, :persistent, false),
          validations: Keyword.get(opts, :validations, []),
          description: Keyword.get(opts, :description, "")
        }
      end
    end
  end
end
