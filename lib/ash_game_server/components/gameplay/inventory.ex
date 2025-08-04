defmodule AshGameServer.Components.Gameplay.Inventory do
  @moduledoc """
  Inventory component for managing entity items and equipment.
  
  Supports item slots, weight limits, and stacking.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type item_id :: String.t()
  @type slot_id :: atom() | integer()
  
  @type item :: %{
    id: item_id(),
    quantity: pos_integer(),
    weight: float(),
    metadata: map()
  }
  
  @type t :: %__MODULE__{
    items: %{slot_id() => item()},
    max_slots: pos_integer(),
    max_weight: float() | nil,
    current_weight: float()
  }
  
  defstruct [
    items: %{},
    max_slots: 20,
    max_weight: nil,
    current_weight: 0.0
  ]
  
  @impl true
  def validate(%__MODULE__{} = inventory) do
    with :ok <- validate_capacity(inventory),
         :ok <- validate_weight(inventory) do
      validate_items(inventory)
    end
  end
  
  defp validate_capacity(%{items: items, max_slots: max_slots}) do
    if map_size(items) <= max_slots do
      :ok
    else
      {:error, "Inventory exceeds maximum slots"}
    end
  end
  
  defp validate_weight(%{max_weight: nil}), do: :ok
  defp validate_weight(%{current_weight: current, max_weight: max}) do
    if current <= max do
      :ok
    else
      {:error, "Inventory exceeds maximum weight"}
    end
  end
  
  defp validate_items(%{items: items}) do
    invalid = Enum.find(items, fn {_slot, item} ->
      not is_map(item) or
      not Map.has_key?(item, :id) or
      Map.get(item, :quantity, 0) <= 0
    end)
    
    if invalid do
      {:error, "Invalid item in inventory"}
    else
      :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = inventory) do
    %{
      items: Map.new(inventory.items, fn {slot, item} ->
        {slot, serialize_item(item)}
      end),
      max_slots: inventory.max_slots,
      max_weight: inventory.max_weight,
      current_weight: Float.round(inventory.current_weight * 1.0, 2)
    }
  end
  
  defp serialize_item(item) do
    %{
      id: item.id,
      quantity: item.quantity,
      weight: Float.round(Map.get(item, :weight, 0.0) * 1.0, 2),
      metadata: Map.get(item, :metadata, %{})
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    items = Map.get(data, :items, %{})
    |> Map.new(fn {slot, item_data} ->
      {slot, deserialize_item(item_data)}
    end)
    
    {:ok, %__MODULE__{
      items: items,
      max_slots: Map.get(data, :max_slots, 20),
      max_weight: Map.get(data, :max_weight),
      current_weight: calculate_weight(items)
    }}
  end
  
  defp deserialize_item(data) do
    %{
      id: Map.get(data, :id, ""),
      quantity: Map.get(data, :quantity, 1),
      weight: Map.get(data, :weight, 0.0) * 1.0,
      metadata: Map.get(data, :metadata, %{})
    }
  end
  
  # Helper functions
  
  @doc """
  Add an item to the inventory.
  """
  def add_item(%__MODULE__{} = inventory, item, slot \\ nil) do
    slot = slot || find_empty_slot(inventory)
    
    cond do
      slot == nil ->
        {:error, :no_space}
      
      not can_add_weight?(inventory, item) ->
        {:error, :too_heavy}
      
      true ->
        new_items = Map.put(inventory.items, slot, item)
        new_weight = inventory.current_weight + Map.get(item, :weight, 0.0) * Map.get(item, :quantity, 1)
        
        {:ok, %__MODULE__{inventory |
          items: new_items,
          current_weight: new_weight
        }}
    end
  end
  
  @doc """
  Remove an item from the inventory.
  """
  def remove_item(%__MODULE__{} = inventory, slot) do
    case Map.get(inventory.items, slot) do
      nil ->
        {:error, :not_found}
      
      item ->
        new_items = Map.delete(inventory.items, slot)
        new_weight = inventory.current_weight - Map.get(item, :weight, 0.0) * Map.get(item, :quantity, 1)
        
        {:ok, %__MODULE__{inventory |
          items: new_items,
          current_weight: max(0.0, new_weight)
        }}
    end
  end
  
  @doc """
  Get an item from a specific slot.
  """
  def get_item(%__MODULE__{items: items}, slot) do
    Map.get(items, slot)
  end
  
  @doc """
  Check if inventory has space for an item.
  """
  def has_space?(%__MODULE__{items: items, max_slots: max_slots}) do
    map_size(items) < max_slots
  end
  
  @doc """
  Check if inventory is full.
  """
  def full?(%__MODULE__{} = inventory) do
    not has_space?(inventory)
  end
  
  @doc """
  Get used and maximum slots.
  """
  def slot_usage(%__MODULE__{items: items, max_slots: max_slots}) do
    {map_size(items), max_slots}
  end
  
  @doc """
  Find items by ID.
  """
  def find_items_by_id(%__MODULE__{items: items}, item_id) do
    items
    |> Enum.filter(fn {_slot, item} -> item.id == item_id end)
    |> Map.new()
  end
  
  @doc """
  Count total quantity of an item type.
  """
  def count_item(%__MODULE__{items: items}, item_id) do
    items
    |> Enum.filter(fn {_slot, item} -> item.id == item_id end)
    |> Enum.reduce(0, fn {_slot, item}, acc ->
      acc + Map.get(item, :quantity, 1)
    end)
  end
  
  # Private helpers
  
  defp find_empty_slot(%__MODULE__{items: items, max_slots: max_slots}) do
    Enum.find(0..(max_slots - 1), fn slot ->
      not Map.has_key?(items, slot)
    end)
  end
  
  defp can_add_weight?(%__MODULE__{max_weight: nil}, _item), do: true
  defp can_add_weight?(%__MODULE__{} = inventory, item) do
    item_weight = Map.get(item, :weight, 0.0) * Map.get(item, :quantity, 1)
    inventory.current_weight + item_weight <= inventory.max_weight
  end
  
  defp calculate_weight(items) do
    Enum.reduce(items, 0.0, fn {_slot, item}, acc ->
      acc + Map.get(item, :weight, 0.0) * Map.get(item, :quantity, 1)
    end)
  end
end