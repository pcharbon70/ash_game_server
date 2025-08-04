defmodule AshGameServer.ECS.EntityArchetype do
  @moduledoc """
  Entity Archetype system for the ECS architecture.

  Provides comprehensive archetype management with:
  - Archetype definitions and component templates
  - Entity spawning from archetypes
  - Archetype variations and inheritance
  - Performance optimization through pre-configured templates
  """

  use GenServer

  alias AshGameServer.ECS.Entity

  @type archetype_name :: atom()
  @type component_template :: %{
    component_name: atom(),
    default_data: map(),
    required: boolean(),
    variations: map()
  }

  @type archetype_definition :: %{
    name: archetype_name(),
    description: String.t(),
    components: [component_template()],
    parent: archetype_name() | nil,
    spawn_config: map(),
    variations: map(),
    metadata: map()
  }

  @type spawn_options :: %{
    variation: atom() | nil,
    component_overrides: map(),
    metadata: map(),
    tags: [atom()],
    parent_id: Entity.entity_id() | nil
  }

  # ETS table for archetype storage
  @archetypes_table :entity_archetypes
  @archetype_stats_table :archetype_stats

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new archetype definition.
  """
  @spec register_archetype(archetype_definition()) :: :ok | {:error, term()}
  def register_archetype(archetype_def) do
    GenServer.call(__MODULE__, {:register_archetype, archetype_def})
  end

  @doc """
  Get an archetype definition by name.
  """
  @spec get_archetype(archetype_name()) :: {:ok, archetype_definition()} | {:error, :not_found}
  def get_archetype(archetype_name) do
    case :ets.lookup(@archetypes_table, archetype_name) do
      [{^archetype_name, definition}] -> {:ok, definition}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all registered archetypes.
  """
  @spec list_archetypes() :: [archetype_name()]
  def list_archetypes do
    :ets.select(@archetypes_table, [{{:"$1", :_}, [], [:"$1"]}])
  end

  @doc """
  Spawn an entity from an archetype.
  """
  @spec spawn_entity(archetype_name(), spawn_options()) :: {:ok, Entity.entity_id()} | {:error, term()}
  def spawn_entity(archetype_name, opts \\ %{}) do
    GenServer.call(__MODULE__, {:spawn_entity, archetype_name, opts})
  end

  @doc """
  Spawn multiple entities from an archetype efficiently.
  """
  @spec spawn_entities(archetype_name(), non_neg_integer(), spawn_options()) ::
    {:ok, [Entity.entity_id()]} | {:error, term()}
  def spawn_entities(archetype_name, count, opts \\ %{}) do
    GenServer.call(__MODULE__, {:spawn_entities, archetype_name, count, opts})
  end

  @doc """
  Update an archetype definition.
  """
  @spec update_archetype(archetype_name(), map()) :: :ok | {:error, term()}
  def update_archetype(archetype_name, updates) do
    GenServer.call(__MODULE__, {:update_archetype, archetype_name, updates})
  end

  @doc """
  Remove an archetype definition.
  """
  @spec remove_archetype(archetype_name()) :: :ok
  def remove_archetype(archetype_name) do
    GenServer.cast(__MODULE__, {:remove_archetype, archetype_name})
  end

  @doc """
  Get archetype statistics and usage metrics.
  """
  @spec get_archetype_stats(archetype_name()) :: map()
  def get_archetype_stats(archetype_name) do
    case :ets.lookup(@archetype_stats_table, archetype_name) do
      [{^archetype_name, stats}] -> stats
      [] -> %{spawn_count: 0, last_spawned: nil, total_spawn_time: 0}
    end
  end

  @doc """
  Get all archetype statistics.
  """
  @spec get_all_stats() :: map()
  def get_all_stats do
    :ets.tab2list(@archetype_stats_table) |> Enum.into(%{})
  end

  @doc """
  Validate an archetype definition.
  """
  @spec validate_archetype(archetype_definition()) :: :ok | {:error, term()}
  def validate_archetype(archetype_def) do
    with :ok <- validate_required_fields(archetype_def),
         :ok <- validate_components(archetype_def.components) do
      validate_inheritance(archetype_def)
    end
  end

  @doc """
  Get the complete component set for an archetype including inherited components.
  """
  @spec get_complete_components(archetype_name()) :: {:ok, [component_template()]} | {:error, term()}
  def get_complete_components(archetype_name) do
    GenServer.call(__MODULE__, {:get_complete_components, archetype_name})
  end

  @doc """
  Create an archetype variation.
  """
  @spec create_variation(archetype_name(), atom(), map()) :: :ok | {:error, term()}
  def create_variation(archetype_name, variation_name, variation_data) do
    GenServer.call(__MODULE__, {:create_variation, archetype_name, variation_name, variation_data})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create archetype storage tables
    :ets.new(@archetypes_table, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@archetype_stats_table, [:named_table, :public, :set])

    # Register built-in archetypes
    register_builtin_archetypes()

    state = %{
      validation_cache: %{},
      component_cache: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_archetype, archetype_def}, _from, state) do
    case validate_archetype(archetype_def) do
      :ok ->
        :ets.insert(@archetypes_table, {archetype_def.name, archetype_def})

        # Initialize stats
        stats = %{
          spawn_count: 0,
          last_spawned: nil,
          total_spawn_time: 0,
          registered_at: DateTime.utc_now()
        }
        :ets.insert(@archetype_stats_table, {archetype_def.name, stats})

        # Clear component cache for this archetype
        updated_state = %{state | component_cache: Map.delete(state.component_cache, archetype_def.name)}

        {:reply, :ok, updated_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:spawn_entity, archetype_name, opts}, _from, state) do
    start_time = System.monotonic_time()

    result = do_spawn_entity(archetype_name, opts, state)

    # Update statistics
    duration = System.monotonic_time() - start_time
    update_spawn_stats(archetype_name, 1, duration)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:spawn_entities, archetype_name, count, opts}, _from, state) do
    start_time = System.monotonic_time()

    result = do_spawn_entities(archetype_name, count, opts, state)

    # Update statistics
    duration = System.monotonic_time() - start_time
    update_spawn_stats(archetype_name, count, duration)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_archetype, archetype_name, updates}, _from, state) do
    case :ets.lookup(@archetypes_table, archetype_name) do
      [{^archetype_name, current_def}] ->
        updated_def = Map.merge(current_def, updates)

        case validate_archetype(updated_def) do
          :ok ->
            :ets.insert(@archetypes_table, {archetype_name, updated_def})

            # Clear caches
            updated_state = %{state |
              component_cache: Map.delete(state.component_cache, archetype_name),
              validation_cache: Map.delete(state.validation_cache, archetype_name)
            }

            {:reply, :ok, updated_state}

          error ->
            {:reply, error, state}
        end

      [] ->
        {:reply, {:error, :archetype_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_complete_components, archetype_name}, _from, state) do
    case Map.get(state.component_cache, archetype_name) do
      nil ->
        result = build_complete_components(archetype_name)
        updated_cache = Map.put(state.component_cache, archetype_name, result)
        updated_state = %{state | component_cache: updated_cache}
        {:reply, result, updated_state}

      cached_result ->
        {:reply, cached_result, state}
    end
  end

  @impl true
  def handle_call({:create_variation, archetype_name, variation_name, variation_data}, _from, state) do
    case :ets.lookup(@archetypes_table, archetype_name) do
      [{^archetype_name, archetype_def}] ->
        updated_variations = Map.put(archetype_def.variations, variation_name, variation_data)
        updated_def = %{archetype_def | variations: updated_variations}

        :ets.insert(@archetypes_table, {archetype_name, updated_def})

        # Clear component cache
        updated_state = %{state | component_cache: Map.delete(state.component_cache, archetype_name)}

        {:reply, :ok, updated_state}

      [] ->
        {:reply, {:error, :archetype_not_found}, state}
    end
  end

  @impl true
  def handle_cast({:remove_archetype, archetype_name}, state) do
    :ets.delete(@archetypes_table, archetype_name)
    :ets.delete(@archetype_stats_table, archetype_name)

    # Clear caches
    updated_state = %{state |
      component_cache: Map.delete(state.component_cache, archetype_name),
      validation_cache: Map.delete(state.validation_cache, archetype_name)
    }

    {:noreply, updated_state}
  end

  # Private Functions

  defp do_spawn_entity(archetype_name, opts, state) do
    with {:ok, complete_components} <- get_complete_components_cached(archetype_name, state),
         {:ok, final_components} <- apply_variations_and_overrides(complete_components, opts) do
      create_entity_with_components(archetype_name, final_components, opts)
    end
  end

  defp do_spawn_entities(archetype_name, count, opts, state) do
    with {:ok, complete_components} <- get_complete_components_cached(archetype_name, state),
         {:ok, final_components} <- apply_variations_and_overrides(complete_components, opts) do

      entity_ids = for _ <- 1..count do
        {:ok, entity_id} = create_entity_with_components(archetype_name, final_components, opts)
        entity_id
      end

      {:ok, entity_ids}
    end
  end

  defp get_complete_components_cached(archetype_name, state) do
    case Map.get(state.component_cache, archetype_name) do
      nil -> build_complete_components(archetype_name)
      cached_result -> cached_result
    end
  end

  defp build_complete_components(archetype_name) do
    case get_archetype(archetype_name) do
      {:ok, archetype_def} ->
        components = collect_inherited_components(archetype_def, [])
        {:ok, components}

      error -> error
    end
  end

  defp collect_inherited_components(archetype_def, visited) do
    if archetype_def.name in visited do
      # Circular inheritance detected
      archetype_def.components
    else
      base_components = get_parent_components(archetype_def, visited)
      # Merge parent components with archetype components (archetype overrides parent)
      merge_component_templates(base_components, archetype_def.components)
    end
  end

  defp get_parent_components(archetype_def, visited) do
    case archetype_def.parent do
      nil -> []
      parent_name -> fetch_parent_components(parent_name, archetype_def.name, visited)
    end
  end

  defp fetch_parent_components(parent_name, current_name, visited) do
    case get_archetype(parent_name) do
      {:ok, parent_def} ->
        collect_inherited_components(parent_def, [current_name | visited])
      _ -> []
    end
  end

  defp merge_component_templates(base_components, override_components) do
    base_map = Enum.into(base_components, %{}, fn comp -> {comp.component_name, comp} end)
    override_map = Enum.into(override_components, %{}, fn comp -> {comp.component_name, comp} end)

    Map.merge(base_map, override_map) |> Map.values()
  end

  defp apply_variations_and_overrides(components, opts) do
    variation = Map.get(opts, :variation)
    overrides = Map.get(opts, :component_overrides, %{})

    updated_components = Enum.map(components, fn component ->
      # Apply variation if specified
      varied_data = case variation do
        nil -> component.default_data
        var_name ->
          Map.get(component.variations, var_name, component.default_data)
      end

      # Apply overrides
      final_data = case Map.get(overrides, component.component_name) do
        nil -> varied_data
        override_data -> Map.merge(varied_data, override_data)
      end

      %{component | default_data: final_data}
    end)

    {:ok, updated_components}
  end

  defp create_entity_with_components(archetype_name, components, opts) do
    entity_opts = [
      archetype: archetype_name,
      metadata: Map.get(opts, :metadata, %{}),
      tags: Map.get(opts, :tags, []),
      parent_id: Map.get(opts, :parent_id)
    ]

    case Entity.create(entity_opts) do
      {:ok, entity} ->
        # Add all components
        Enum.each(components, fn component ->
          AshGameServer.Storage.add_component(
            entity.id,
            component.component_name,
            component.default_data
          )
        end)

        {:ok, entity.id}

      error -> error
    end
  end

  defp update_spawn_stats(archetype_name, count, duration) do
    case :ets.lookup(@archetype_stats_table, archetype_name) do
      [{^archetype_name, stats}] ->
        updated_stats = %{stats |
          spawn_count: stats.spawn_count + count,
          last_spawned: DateTime.utc_now(),
          total_spawn_time: stats.total_spawn_time + duration
        }
        :ets.insert(@archetype_stats_table, {archetype_name, updated_stats})

      [] ->
        # Initialize stats if not present
        stats = %{
          spawn_count: count,
          last_spawned: DateTime.utc_now(),
          total_spawn_time: duration,
          registered_at: DateTime.utc_now()
        }
        :ets.insert(@archetype_stats_table, {archetype_name, stats})
    end
  end

  defp validate_required_fields(archetype_def) do
    required_fields = [:name, :components]

    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(archetype_def, field)
    end)

    if missing_fields == [] do
      :ok
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  defp validate_components(components) when is_list(components) do
    invalid_components = Enum.reject(components, &valid_component_template?/1)

    if invalid_components == [] do
      :ok
    else
      {:error, {:invalid_components, invalid_components}}
    end
  end

  defp validate_components(_), do: {:error, :components_must_be_list}

  defp valid_component_template?(component) do
    Map.has_key?(component, :component_name) and
    Map.has_key?(component, :default_data) and
    is_atom(component.component_name) and
    is_map(component.default_data)
  end

  defp validate_inheritance(archetype_def) do
    case archetype_def.parent do
      nil -> :ok
      parent_name ->
        case get_archetype(parent_name) do
          {:ok, _} ->
            # Check for circular inheritance
            check_circular_inheritance(archetype_def.name, parent_name, [])
          {:error, :not_found} ->
            {:error, {:parent_not_found, parent_name}}
        end
    end
  end

  defp check_circular_inheritance(current_name, parent_name, visited) do
    if current_name == parent_name or current_name in visited do
      {:error, {:circular_inheritance, current_name}}
    else
      check_parent_hierarchy(current_name, parent_name, visited)
    end
  end

  defp check_parent_hierarchy(current_name, parent_name, visited) do
    case get_archetype(parent_name) do
      {:ok, parent_def} ->
        check_grandparent(current_name, parent_def, parent_name, visited)
      _ -> :ok
    end
  end

  defp check_grandparent(current_name, parent_def, parent_name, visited) do
    case parent_def.parent do
      nil -> :ok
      grandparent_name ->
        check_circular_inheritance(current_name, grandparent_name, [parent_name | visited])
    end
  end

  defp register_builtin_archetypes do
    # Player archetype
    player_archetype = %{
      name: :player,
      description: "Base player entity with core game components",
      components: [
        %{
          component_name: :position,
          default_data: %{x: 0.0, y: 0.0, z: 0.0, rotation: 0.0},
          required: true,
          variations: %{
            spawn_point_1: %{x: 100.0, y: 100.0, z: 0.0, rotation: 0.0},
            spawn_point_2: %{x: 200.0, y: 200.0, z: 0.0, rotation: 180.0}
          }
        },
        %{
          component_name: :health,
          default_data: %{current: 100, max: 100, regeneration_rate: 1.0},
          required: true,
          variations: %{
            veteran: %{current: 150, max: 150, regeneration_rate: 1.5},
            rookie: %{current: 75, max: 75, regeneration_rate: 0.8}
          }
        },
        %{
          component_name: :inventory,
          default_data: %{slots: 20, items: [], weight: 0.0, max_weight: 100.0},
          required: true,
          variations: %{
            large: %{slots: 40, max_weight: 200.0},
            small: %{slots: 10, max_weight: 50.0}
          }
        },
        %{
          component_name: :player_stats,
          default_data: %{level: 1, experience: 0, skill_points: 0},
          required: true,
          variations: %{}
        }
      ],
      parent: nil,
      spawn_config: %{
        default_tags: [:player, :controllable],
        auto_register: true
      },
      variations: %{
        warrior: %{default_tags: [:player, :controllable, :warrior]},
        mage: %{default_tags: [:player, :controllable, :mage]},
        archer: %{default_tags: [:player, :controllable, :archer]}
      },
      metadata: %{
        category: :player,
        description: "Standard player character"
      }
    }

    # NPC archetype
    npc_archetype = %{
      name: :npc,
      description: "Base NPC entity with AI and interaction components",
      components: [
        %{
          component_name: :position,
          default_data: %{x: 0.0, y: 0.0, z: 0.0, rotation: 0.0},
          required: true,
          variations: %{}
        },
        %{
          component_name: :health,
          default_data: %{current: 50, max: 50, regeneration_rate: 0.5},
          required: true,
          variations: %{
            boss: %{current: 500, max: 500, regeneration_rate: 5.0},
            minion: %{current: 25, max: 25, regeneration_rate: 0.0}
          }
        },
        %{
          component_name: :ai_controller,
          default_data: %{
            behavior: :passive,
            target_id: nil,
            patrol_points: [],
            aggro_range: 10.0
          },
          required: true,
          variations: %{
            aggressive: %{behavior: :aggressive, aggro_range: 15.0},
            guard: %{behavior: :guard, aggro_range: 8.0}
          }
        }
      ],
      parent: nil,
      spawn_config: %{
        default_tags: [:npc, :ai_controlled],
        auto_register: true
      },
      variations: %{
        merchant: %{default_tags: [:npc, :merchant, :interactive]},
        guard: %{default_tags: [:npc, :guard, :ai_controlled]},
        enemy: %{default_tags: [:npc, :enemy, :ai_controlled]}
      },
      metadata: %{
        category: :npc,
        description: "Standard NPC character"
      }
    }

    # Item archetype
    item_archetype = %{
      name: :item,
      description: "Base item entity for collectibles and equipment",
      components: [
        %{
          component_name: :position,
          default_data: %{x: 0.0, y: 0.0, z: 0.0, rotation: 0.0},
          required: true,
          variations: %{}
        },
        %{
          component_name: :item_properties,
          default_data: %{
            name: "Unknown Item",
            description: "",
            weight: 1.0,
            value: 0,
            stackable: false,
            max_stack: 1
          },
          required: true,
          variations: %{
            weapon: %{weight: 5.0, value: 100, stackable: false},
            consumable: %{weight: 0.1, value: 10, stackable: true, max_stack: 99},
            treasure: %{weight: 0.5, value: 1000, stackable: false}
          }
        }
      ],
      parent: nil,
      spawn_config: %{
        default_tags: [:item, :collectible],
        auto_register: true
      },
      variations: %{
        weapon: %{default_tags: [:item, :weapon, :equipment]},
        armor: %{default_tags: [:item, :armor, :equipment]},
        consumable: %{default_tags: [:item, :consumable]}
      },
      metadata: %{
        category: :item,
        description: "Standard game item"
      }
    }

    # Register the built-in archetypes
    :ets.insert(@archetypes_table, {:player, player_archetype})
    :ets.insert(@archetypes_table, {:npc, npc_archetype})
    :ets.insert(@archetypes_table, {:item, item_archetype})

    # Initialize stats for built-in archetypes
    Enum.each([:player, :npc, :item], fn archetype_name ->
      stats = %{
        spawn_count: 0,
        last_spawned: nil,
        total_spawn_time: 0,
        registered_at: DateTime.utc_now()
      }
      :ets.insert(@archetype_stats_table, {archetype_name, stats})
    end)

    :ok
  end
end
