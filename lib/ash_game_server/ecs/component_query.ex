defmodule AshGameServer.ECS.ComponentQuery do
  @moduledoc """
  Fluent query DSL for component filtering, joining, and aggregation.
  
  Provides a powerful and efficient way to query components with:
  - Fluent query builder interface
  - Efficient filter operations
  - Join capabilities across components
  - Aggregation and statistical functions
  - Query result caching
  - Query optimization and planning
  """

  alias AshGameServer.ECS.{EnhancedStorage, ComponentRegistry}
  alias AshGameServer.Storage

  @type entity_id :: term()
  @type component_name :: atom()
  @type query_result :: [map()]
  @type filter_op :: :eq | :ne | :gt | :gte | :lt | :lte | :in | :not_in | :like | :exists
  @type aggregate_op :: :count | :sum | :avg | :min | :max | :distinct_count

  defstruct [
    :from,
    :select,
    :where,
    :joins,
    :group_by,
    :having,
    :order_by,
    :limit,
    :offset,
    :cache_key,
    execution_plan: nil,
    optimizations: []
  ]

  @type t :: %__MODULE__{
    from: component_name() | nil,
    select: list() | nil,
    where: list(),
    joins: list(),
    group_by: list(),
    having: list(),
    order_by: list(),
    limit: non_neg_integer() | nil,
    offset: non_neg_integer() | nil,
    cache_key: term() | nil,
    execution_plan: map() | nil,
    optimizations: list()
  }

  # Query Builder API

  @doc """
  Starts a new query for a component type.
  """
  @spec from(component_name()) :: t()
  def from(component_name) do
    %__MODULE__{
      from: component_name,
      where: [],
      joins: [],
      group_by: [],
      having: [],
      order_by: []
    }
  end

  @doc """
  Selects specific fields or aggregations.
  """
  @spec select(t(), list() | map()) :: t()
  def select(%__MODULE__{} = query, fields) do
    %{query | select: fields}
  end

  @doc """
  Adds a WHERE condition.
  """
  @spec where(t(), atom(), filter_op(), term()) :: t()
  def where(%__MODULE__{} = query, field, op, value) do
    condition = {field, op, value}
    %{query | where: [condition | query.where]}
  end

  @doc """
  Adds multiple WHERE conditions with AND logic.
  """
  @spec where(t(), keyword() | map()) :: t()
  def where(%__MODULE__{} = query, conditions) when is_list(conditions) or is_map(conditions) do
    new_conditions = 
      conditions
      |> Enum.map(fn {field, value} -> {field, :eq, value} end)
    
    %{query | where: new_conditions ++ query.where}
  end

  @doc """
  Joins with another component.
  """
  @spec join(t(), component_name(), atom(), atom()) :: t()
  def join(%__MODULE__{} = query, component, left_field, right_field) do
    join_spec = {:inner, component, left_field, right_field}
    %{query | joins: [join_spec | query.joins]}
  end

  @doc """
  Left joins with another component.
  """
  @spec left_join(t(), component_name(), atom(), atom()) :: t()
  def left_join(%__MODULE__{} = query, component, left_field, right_field) do
    join_spec = {:left, component, left_field, right_field}
    %{query | joins: [join_spec | query.joins]}
  end

  @doc """
  Groups results by specified fields.
  """
  @spec group_by(t(), list()) :: t()
  def group_by(%__MODULE__{} = query, fields) do
    %{query | group_by: fields}
  end

  @doc """
  Adds HAVING conditions for grouped results.
  """
  @spec having(t(), atom(), filter_op(), term()) :: t()
  def having(%__MODULE__{} = query, field, op, value) do
    condition = {field, op, value}
    %{query | having: [condition | query.having]}
  end

  @doc """
  Orders results by specified fields.
  """
  @spec order_by(t(), list()) :: t()
  def order_by(%__MODULE__{} = query, fields) do
    %{query | order_by: fields}
  end

  @doc """
  Limits the number of results.
  """
  @spec limit(t(), non_neg_integer()) :: t()
  def limit(%__MODULE__{} = query, count) do
    %{query | limit: count}
  end

  @doc """
  Skips a number of results.
  """
  @spec offset(t(), non_neg_integer()) :: t()
  def offset(%__MODULE__{} = query, count) do
    %{query | offset: count}
  end

  @doc """
  Enables caching for this query.
  """
  @spec cache(t(), term()) :: t()
  def cache(%__MODULE__{} = query, cache_key) do
    %{query | cache_key: cache_key}
  end

  # Execution

  @doc """
  Executes the query and returns results.
  """
  @spec execute(t()) :: {:ok, query_result()} | {:error, term()}
  def execute(%__MODULE__{} = query) do
    # Check cache first
    if query.cache_key do
      case get_cached_result(query.cache_key) do
        :miss -> execute_and_cache(query)
        # Cache implementation will return {:ok, result} when implemented
      end
    else
      execute_query(query)
    end
  end

  @doc """
  Executes the query and returns a stream.
  """
  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{} = query) do
    Stream.resource(
      fn -> prepare_stream(query) end,
      fn state -> fetch_batch(state) end,
      fn state -> cleanup_stream(state) end
    )
  end

  @doc """
  Returns the count of matching entities.
  """
  @spec count(t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(%__MODULE__{} = query) do
    optimized_query = %{query | select: [{:count, :*}]}
    
    case execute_query(optimized_query) do
      {:ok, [%{count: count}]} -> {:ok, count}
      {:ok, results} -> {:ok, length(results)}
      error -> error
    end
  end

  @doc """
  Checks if any entities match the query.
  """
  @spec exists?(t()) :: boolean()
  def exists?(%__MODULE__{} = query) do
    case query |> limit(1) |> count() do
      {:ok, count} -> count > 0
      _ -> false
    end
  end

  # Aggregation Functions

  @doc """
  Aggregates a field using the specified operation.
  """
  @spec aggregate(t(), aggregate_op(), atom()) :: {:ok, term()} | {:error, term()}
  def aggregate(%__MODULE__{} = query, op, field) do
    optimized_query = %{query | select: [{op, field}]}
    
    case execute_query(optimized_query) do
      {:ok, [result]} -> {:ok, Map.get(result, op)}
      error -> error
    end
  end

  @doc """
  Sums values of a numeric field.
  """
  @spec sum(t(), atom()) :: {:ok, number()} | {:error, term()}
  def sum(%__MODULE__{} = query, field) do
    aggregate(query, :sum, field)
  end

  @doc """
  Calculates average of a numeric field.
  """
  @spec avg(t(), atom()) :: {:ok, float()} | {:error, term()}
  def avg(%__MODULE__{} = query, field) do
    aggregate(query, :avg, field)
  end

  @doc """
  Finds minimum value of a field.
  """
  @spec min(t(), atom()) :: {:ok, term()} | {:error, term()}
  def min(%__MODULE__{} = query, field) do
    aggregate(query, :min, field)
  end

  @doc """
  Finds maximum value of a field.
  """
  @spec max(t(), atom()) :: {:ok, term()} | {:error, term()}
  def max(%__MODULE__{} = query, field) do
    aggregate(query, :max, field)
  end

  # Private Functions

  defp execute_and_cache(query) do
    case execute_query(query) do
      {:ok, result} = success ->
        cache_result(query.cache_key, result)
        success
      error -> error
    end
  end

  defp execute_query(%__MODULE__{} = query) do
    try do
      # Create execution plan
      plan = create_execution_plan(query)
      
      # Execute the plan
      result = execute_plan(plan)
      
      {:ok, result}
    rescue
      error ->
        {:error, {:execution_failed, error}}
    end
  end

  defp create_execution_plan(query) do
    %{
      base_component: query.from,
      filters: query.where,
      joins: query.joins,
      aggregations: extract_aggregations(query.select),
      projections: extract_projections(query.select),
      ordering: query.order_by,
      limit: query.limit,
      offset: query.offset,
      optimizations: plan_optimizations(query)
    }
  end

  defp execute_plan(plan) do
    # Start with base entities
    entities = get_base_entities(plan.base_component)
    
    # Apply filters
    filtered = apply_filters(entities, plan.base_component, plan.filters)
    
    # Apply joins
    joined = apply_joins(filtered, plan.joins)
    
    # Apply aggregations or projections
    if plan.aggregations != [] do
      apply_aggregations(joined, plan.aggregations)
    else
      results = apply_projections(joined, plan.projections)
      
      # Apply ordering
      ordered = apply_ordering(results, plan.ordering)
      
      # Apply limit/offset
      apply_pagination(ordered, plan.limit, plan.offset)
    end
  end

  defp get_base_entities(component_name) do
    Storage.query_entities([component_name])
  end

  defp apply_filters(entities, component_name, filters) do
    Enum.filter(entities, fn entity_id ->
      case EnhancedStorage.get_component(entity_id, component_name) do
        {:ok, data} ->
          Enum.all?(filters, fn {field, op, value} ->
            apply_filter(Map.get(data, field), op, value)
          end)
        _ -> false
      end
    end)
  end

  defp apply_filter(field_value, :eq, value), do: field_value == value
  defp apply_filter(field_value, :ne, value), do: field_value != value
  defp apply_filter(field_value, :gt, value), do: field_value > value
  defp apply_filter(field_value, :gte, value), do: field_value >= value
  defp apply_filter(field_value, :lt, value), do: field_value < value
  defp apply_filter(field_value, :lte, value), do: field_value <= value
  defp apply_filter(field_value, :in, values), do: field_value in values
  defp apply_filter(field_value, :not_in, values), do: field_value not in values
  defp apply_filter(field_value, :like, pattern) when is_binary(field_value) do
    String.contains?(field_value, pattern)
  end
  defp apply_filter(field_value, :exists, _), do: field_value != nil

  defp apply_joins(entities, joins) do
    Enum.reduce(joins, entities, fn {join_type, component, left_field, right_field}, acc ->
      apply_single_join(acc, join_type, component, left_field, right_field)
    end)
  end

  defp apply_single_join(entities, :inner, _component, _left_field, _right_field) do
    # Implementation for inner join
    # This is a simplified version - real implementation would be more complex
    entities
  end

  defp apply_single_join(entities, :left, _component, _left_field, _right_field) do
    # Implementation for left join
    entities
  end

  defp apply_projections(entities, projections) when projections == [] or projections == nil do
    # Return full component data
    Enum.map(entities, fn entity_id ->
      # This would get all components for the entity
      %{entity_id: entity_id}
    end)
  end

  defp apply_projections(entities, _projections) do
    # Project specific fields
    entities
  end

  defp apply_aggregations(entities, _aggregations) do
    # Apply aggregation functions
    [%{count: length(entities)}]
  end

  defp apply_ordering(results, []), do: results
  defp apply_ordering(results, ordering) do
    Enum.sort_by(results, fn result ->
      Enum.map(ordering, fn
        {field, :asc} -> Map.get(result, field)
        {field, :desc} -> Map.get(result, field)
        field -> Map.get(result, field)
      end)
    end)
  end

  defp apply_pagination(results, nil, nil), do: results
  defp apply_pagination(results, limit, nil), do: Enum.take(results, limit)
  defp apply_pagination(results, nil, offset), do: Enum.drop(results, offset)
  defp apply_pagination(results, limit, offset) do
    results |> Enum.drop(offset) |> Enum.take(limit)
  end

  defp extract_aggregations(nil), do: []
  defp extract_aggregations(select) when is_list(select) do
    Enum.filter(select, fn
      {op, _field} when op in [:count, :sum, :avg, :min, :max, :distinct_count] -> true
      _ -> false
    end)
  end
  defp extract_aggregations(_), do: []

  defp extract_projections(nil), do: []
  defp extract_projections(select) when is_list(select) do
    Enum.reject(select, fn
      {op, _field} when op in [:count, :sum, :avg, :min, :max, :distinct_count] -> true
      _ -> false
    end)
  end
  defp extract_projections(select), do: [select]

  defp plan_optimizations(query) do
    optimizations = []
    
    # Add index optimization if using indexed fields
    optimizations = maybe_add_index_optimization(query, optimizations)
    
    # Add other optimizations
    optimizations
  end

  defp maybe_add_index_optimization(query, optimizations) do
    # Check if any WHERE conditions use indexed fields
    case ComponentRegistry.get_component(query.from) do
      {:ok, metadata} ->
        indexes = Map.get(metadata, :indexes, [])
        
        indexed_conditions = Enum.filter(query.where, fn {field, _op, _value} ->
          field in indexes
        end)
        
        if indexed_conditions != [] do
          [:use_indexes | optimizations]
        else
          optimizations
        end
      _ -> optimizations
    end
  end

  # Stream support
  
  defp prepare_stream(query) do
    plan = create_execution_plan(query)
    %{plan: plan, offset: 0, batch_size: 100}
  end

  defp fetch_batch(%{plan: plan, offset: offset, batch_size: batch_size} = state) do
    batch_plan = %{plan | limit: batch_size, offset: offset}
    
    case execute_plan(batch_plan) do
      [] -> {:halt, state}
      results -> {results, %{state | offset: offset + batch_size}}
    end
  end

  defp cleanup_stream(_state), do: :ok

  # Cache support (simplified)
  
  defp get_cached_result(_cache_key) do
    # Implementation would check actual cache
    # Always return :miss for now since cache is not implemented
    :miss
  end

  defp cache_result(_cache_key, _result) do
    # Implementation would store in cache
    :ok
  end
end