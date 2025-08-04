defmodule AshGameServer.Components.AI.Behavior do
  @moduledoc """
  Behavior component for AI decision trees and state machines.
  
  Manages behavior trees, conditions, and action sequences.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type node_type :: :sequence | :selector | :parallel | :action | :condition
  @type node_status :: :running | :success | :failure
  
  @type behavior_node :: %{
    id: String.t(),
    type: node_type(),
    children: [behavior_node()],
    action: atom() | nil,
    condition: (map() -> boolean()) | nil,
    status: node_status()
  }
  
  @type t :: %__MODULE__{
    tree: behavior_node() | nil,
    current_node: String.t() | nil,
    blackboard: map(),
    running_nodes: [String.t()],
    completed_actions: [atom()]
  }
  
  defstruct [
    tree: nil,
    current_node: nil,
    blackboard: %{},
    running_nodes: [],
    completed_actions: []
  ]
  
  @impl true
  def validate(%__MODULE__{} = behavior) do
    cond do
      behavior.tree != nil and not valid_tree?(behavior.tree) ->
        {:error, "Invalid behavior tree structure"}
      
      not is_map(behavior.blackboard) ->
        {:error, "Blackboard must be a map"}
      
      not is_list(behavior.running_nodes) ->
        {:error, "Running nodes must be a list"}
      
      true ->
        :ok
    end
  end
  
  defp valid_tree?(node) when is_map(node) do
    Map.has_key?(node, :id) and
    Map.has_key?(node, :type) and
    Map.get(node, :type) in [:sequence, :selector, :parallel, :action, :condition]
  end
  defp valid_tree?(_), do: false
  
  @impl true
  def serialize(%__MODULE__{} = behavior) do
    %{
      tree: serialize_tree(behavior.tree),
      current_node: behavior.current_node,
      blackboard: behavior.blackboard,
      running_nodes: behavior.running_nodes,
      completed_actions: behavior.completed_actions
    }
  end
  
  defp serialize_tree(nil), do: nil
  defp serialize_tree(node) do
    %{
      id: node.id,
      type: node.type,
      children: Enum.map(Map.get(node, :children, []), &serialize_tree/1),
      action: Map.get(node, :action),
      status: Map.get(node, :status, :running)
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      tree: deserialize_tree(Map.get(data, :tree)),
      current_node: Map.get(data, :current_node),
      blackboard: Map.get(data, :blackboard, %{}),
      running_nodes: Map.get(data, :running_nodes, []),
      completed_actions: Map.get(data, :completed_actions, [])
    }}
  end
  
  defp deserialize_tree(nil), do: nil
  defp deserialize_tree(data) when is_map(data) do
    %{
      id: Map.get(data, :id, ""),
      type: Map.get(data, :type, :action),
      children: Enum.map(Map.get(data, :children, []), &deserialize_tree/1),
      action: Map.get(data, :action),
      condition: nil,  # Conditions can't be deserialized
      status: Map.get(data, :status, :running)
    }
  end
  
  # Helper functions
  
  @doc """
  Create a new behavior with an empty blackboard.
  """
  def new(tree \\ nil) do
    %__MODULE__{
      tree: tree,
      blackboard: %{}
    }
  end
  
  @doc """
  Create a sequence node (all children must succeed).
  """
  def sequence(id, children) do
    %{
      id: id,
      type: :sequence,
      children: children,
      status: :running
    }
  end
  
  @doc """
  Create a selector node (first child to succeed).
  """
  def selector(id, children) do
    %{
      id: id,
      type: :selector,
      children: children,
      status: :running
    }
  end
  
  @doc """
  Create an action node.
  """
  def action(id, action_name) do
    %{
      id: id,
      type: :action,
      action: action_name,
      children: [],
      status: :running
    }
  end
  
  @doc """
  Create a condition node.
  """
  def condition(id, check_fn) do
    %{
      id: id,
      type: :condition,
      condition: check_fn,
      children: [],
      status: :running
    }
  end
  
  @doc """
  Set a value in the blackboard.
  """
  def set_blackboard(%__MODULE__{} = behavior, key, value) do
    %__MODULE__{behavior |
      blackboard: Map.put(behavior.blackboard, key, value)
    }
  end
  
  @doc """
  Get a value from the blackboard.
  """
  def get_blackboard(%__MODULE__{} = behavior, key, default \\ nil) do
    Map.get(behavior.blackboard, key, default)
  end
  
  @doc """
  Clear the blackboard.
  """
  def clear_blackboard(%__MODULE__{} = behavior) do
    %__MODULE__{behavior | blackboard: %{}}
  end
  
  @doc """
  Mark an action as completed.
  """
  def complete_action(%__MODULE__{} = behavior, action) do
    %__MODULE__{behavior |
      completed_actions: [action | behavior.completed_actions]
    }
  end
  
  @doc """
  Reset behavior tree execution.
  """
  def reset(%__MODULE__{} = behavior) do
    %__MODULE__{behavior |
      current_node: nil,
      running_nodes: [],
      completed_actions: []
    }
  end
  
  @doc """
  Simple behavior tree evaluation (basic implementation).
  """
  def evaluate(%__MODULE__{tree: nil} = behavior), do: {:success, behavior}
  def evaluate(%__MODULE__{} = behavior) do
    case evaluate_node(behavior.tree, behavior) do
      {:success, new_behavior} -> {:success, new_behavior}
      {:failure, new_behavior} -> {:failure, new_behavior}
      {:running, new_behavior} -> {:running, new_behavior}
    end
  end
  
  defp evaluate_node(%{type: :action, action: action} = _node, behavior) do
    # In a real implementation, this would execute the action
    {:running, complete_action(behavior, action)}
  end
  
  defp evaluate_node(%{type: :condition, condition: check_fn} = _node, behavior) when is_function(check_fn) do
    if check_fn.(behavior.blackboard) do
      {:success, behavior}
    else
      {:failure, behavior}
    end
  end
  
  defp evaluate_node(%{type: :sequence, children: children}, behavior) do
    # Execute children in sequence until one fails
    Enum.reduce_while(children, {:success, behavior}, fn child, {_status, beh} ->
      case evaluate_node(child, beh) do
        {:failure, new_beh} -> {:halt, {:failure, new_beh}}
        {:running, new_beh} -> {:halt, {:running, new_beh}}
        {:success, new_beh} -> {:cont, {:success, new_beh}}
      end
    end)
  end
  
  defp evaluate_node(%{type: :selector, children: children}, behavior) do
    # Execute children until one succeeds
    Enum.reduce_while(children, {:failure, behavior}, fn child, {_status, beh} ->
      case evaluate_node(child, beh) do
        {:success, new_beh} -> {:halt, {:success, new_beh}}
        {:running, new_beh} -> {:halt, {:running, new_beh}}
        {:failure, new_beh} -> {:cont, {:failure, new_beh}}
      end
    end)
  end
  
  defp evaluate_node(_node, behavior), do: {:success, behavior}
end