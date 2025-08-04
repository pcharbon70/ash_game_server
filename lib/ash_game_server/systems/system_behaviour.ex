defmodule AshGameServer.Systems.SystemBehaviour do
  @moduledoc """
  Behaviour definition for ECS systems with lifecycle management.

  Systems implementing this behaviour can process entities, manage state,
  and coordinate with other systems in the game loop.
  """

  @type entity_id :: term()
  @type component_data :: map()
  @type system_state :: term()
  @type system_config :: map()
  @type system_result :: {:ok, system_state()} | {:error, term()}
  @type process_result :: {:ok, component_data()} | {:skip, reason :: term()} | {:error, term()}
  @type priority :: :critical | :high | :medium | :low | :idle

  @doc """
  Initialize the system with configuration.

  Called once when the system starts. Should return the initial state.
  """
  @callback init(config :: system_config()) :: {:ok, system_state()} | {:error, term()}

  @doc """
  Process a single entity with its components.

  Called for each entity that matches the system's query requirements.
  Should return updated component data or skip/error.
  """
  @callback process_entity(
    entity_id :: entity_id(),
    components :: component_data(),
    state :: system_state()
  ) :: process_result()

  @doc """
  Execute system logic for all matching entities.

  Called once per tick/frame. Can process entities in batch.
  """
  @callback execute(
    entities :: [{entity_id(), component_data()}],
    state :: system_state()
  ) :: system_result()

  @doc """
  Handle system-specific events.

  Called when events are dispatched to the system.
  """
  @callback handle_event(
    event :: term(),
    state :: system_state()
  ) :: system_result()

  @doc """
  Called before system execution begins.

  Can be used for setup, resource allocation, or validation.
  """
  @callback before_execute(state :: system_state()) :: system_result()

  @doc """
  Called after system execution completes.

  Can be used for cleanup, metrics collection, or state updates.
  """
  @callback after_execute(state :: system_state()) :: system_result()

  @doc """
  Get the system's priority level.

  Used for execution ordering.
  """
  @callback priority() :: priority()

  @doc """
  Get required components for this system.

  Entities must have all required components to be processed.
  """
  @callback required_components() :: [atom()]

  @doc """
  Get optional components for this system.

  Entities may have these components, but they're not required.
  """
  @callback optional_components() :: [atom()]

  @doc """
  Get excluded components for this system.

  Entities with any excluded components will not be processed.
  """
  @callback excluded_components() :: [atom()]

  @doc """
  Determine if the system should run this tick.

  Can be used for conditional execution based on time, events, or state.
  """
  @callback should_run?(state :: system_state()) :: boolean()

  @doc """
  Clean up system resources.

  Called when the system is being shut down.
  """
  @callback terminate(reason :: term(), state :: system_state()) :: :ok

  # Optional callbacks with default implementations
  @optional_callbacks [
    handle_event: 2,
    before_execute: 1,
    after_execute: 1,
    optional_components: 0,
    excluded_components: 0,
    should_run?: 1,
    terminate: 2
  ]

  @doc """
  Use this module to implement the SystemBehaviour.

  Provides default implementations for optional callbacks.
  """
  defmacro __using__(opts \\ []) do
    quote do
      @behaviour AshGameServer.Systems.SystemBehaviour

      # Default implementations for optional callbacks

      def handle_event(_event, state), do: {:ok, state}
      def before_execute(state), do: {:ok, state}
      def after_execute(state), do: {:ok, state}
      def optional_components, do: []
      def excluded_components, do: []
      def should_run?(_state), do: true
      def terminate(_reason, _state), do: :ok

      defoverridable [
        handle_event: 2,
        before_execute: 1,
        after_execute: 1,
        optional_components: 0,
        excluded_components: 0,
        should_run?: 1,
        terminate: 2
      ]

      # Helper functions for system implementation

      @doc """
      Query entities that match this system's requirements.
      """
      def query_entities do
        # Return empty list for now, actual implementation would query ECS
        []
      end

      @doc """
      Get the system's configuration.
      """
      def config do
        unquote(opts)
      end
    end
  end
end
