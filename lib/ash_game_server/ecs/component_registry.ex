defmodule AshGameServer.ECS.ComponentRegistry do
  @moduledoc """
  Registry for managing component types and their metadata.
  
  Provides centralized management of:
  - Component type registration
  - Metadata lookup
  - Schema validation
  - Version management
  - Migration coordination
  """
  use GenServer
  
  # alias AshGameServer.ECS.ComponentBehaviour  # TODO: Will be used for type checking
  
  @type component_module :: module()
  @type component_name :: atom()
  
  @registry_table :component_registry
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a component module.
  """
  @spec register_component(component_module()) :: :ok | {:error, term()}
  def register_component(module) do
    GenServer.call(__MODULE__, {:register, module})
  end
  
  @doc """
  Gets component metadata by name.
  """
  @spec get_component(component_name()) :: {:ok, map()} | {:error, :not_found}
  def get_component(name) do
    case :ets.lookup(@registry_table, name) do
      [{^name, metadata}] -> {:ok, metadata}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Lists all registered components.
  """
  @spec list_components() :: [map()]
  def list_components do
    :ets.tab2list(@registry_table)
    |> Enum.map(fn {_name, metadata} -> metadata end)
  end
  
  @doc """
  Gets components by criteria.
  """
  @spec find_components(keyword()) :: [map()]
  def find_components(criteria) do
    list_components()
    |> Enum.filter(fn metadata ->
      Enum.all?(criteria, fn {key, value} ->
        Map.get(metadata, key) == value
      end)
    end)
  end
  
  @doc """
  Validates component data against registered schema.
  """
  @spec validate_component(component_name(), map()) :: :ok | {:error, term()}
  def validate_component(name, data) do
    with {:ok, metadata} <- get_component(name),
         module <- Map.get(metadata, :module) do
      module.validate(data)
    end
  end
  
  @doc """
  Gets the current version of a component.
  """
  @spec get_version(component_name()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_version(name) do
    case get_component(name) do
      {:ok, metadata} -> {:ok, Map.get(metadata, :version)}
      error -> error
    end
  end
  
  @doc """
  Checks if a component supports migration from one version to another.
  """
  @spec can_migrate?(component_name(), non_neg_integer(), non_neg_integer()) :: boolean()
  def can_migrate?(name, from_version, to_version) do
    case get_component(name) do
      {:ok, metadata} ->
        module = Map.get(metadata, :module)
        function_exported?(module, :migrate, 3) and from_version < to_version
      _ -> false
    end
  end
  
  @doc """
  Migrates component data to the latest version.
  """
  @spec migrate_component(component_name(), map(), non_neg_integer()) :: 
    {:ok, map()} | {:error, term()}
  def migrate_component(name, data, from_version) do
    with {:ok, metadata} <- get_component(name),
         to_version <- Map.get(metadata, :version),
         module <- Map.get(metadata, :module) do
      
      if from_version == to_version do
        {:ok, data}
      else
        module.migrate(data, from_version, to_version)
      end
    end
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    :ets.new(@registry_table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:register, module}, _from, state) do
    try do
      metadata = module.metadata()
      
      # Validate the module implements the behaviour
      if function_exported?(module, :metadata, 0) do
        enhanced_metadata = Map.put(metadata, :module, module)
        name = Map.get(metadata, :name)
        
        :ets.insert(@registry_table, {name, enhanced_metadata})
        {:reply, :ok, state}
      else
        {:reply, {:error, :invalid_component}, state}
      end
    rescue
      error ->
        {:reply, {:error, {:registration_failed, error}}, state}
    end
  end
  
  @impl true
  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end
end