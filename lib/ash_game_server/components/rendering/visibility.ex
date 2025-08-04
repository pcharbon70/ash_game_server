defmodule AshGameServer.Components.Rendering.Visibility do
  @moduledoc """
  Visibility component for controlling entity rendering.
  
  Manages visibility flags, render layers, and culling settings.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type render_layer :: :default | :background | :foreground | :ui | :debug | atom()
  
  @type t :: %__MODULE__{
    visible: boolean(),
    render_layer: render_layer(),
    render_order: integer(),
    cull_distance: float() | nil,
    always_render: boolean(),
    cast_shadows: boolean(),
    receive_shadows: boolean()
  }
  
  defstruct [
    visible: true,
    render_layer: :default,
    render_order: 0,
    cull_distance: nil,
    always_render: false,
    cast_shadows: true,
    receive_shadows: true
  ]
  
  @impl true
  def validate(%__MODULE__{} = visibility) do
    cond do
      visibility.cull_distance != nil and visibility.cull_distance < 0 ->
        {:error, "Cull distance cannot be negative"}
      
      not is_boolean(visibility.visible) ->
        {:error, "Visible must be a boolean"}
      
      not is_integer(visibility.render_order) ->
        {:error, "Render order must be an integer"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = visibility) do
    %{
      visible: visibility.visible,
      render_layer: visibility.render_layer,
      render_order: visibility.render_order,
      cull_distance: visibility.cull_distance,
      always_render: visibility.always_render,
      cast_shadows: visibility.cast_shadows,
      receive_shadows: visibility.receive_shadows
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      visible: Map.get(data, :visible, true),
      render_layer: Map.get(data, :render_layer, :default),
      render_order: Map.get(data, :render_order, 0),
      cull_distance: Map.get(data, :cull_distance),
      always_render: Map.get(data, :always_render, false),
      cast_shadows: Map.get(data, :cast_shadows, true),
      receive_shadows: Map.get(data, :receive_shadows, true)
    }}
  end
  
  # Helper functions
  
  @doc """
  Create a visibility component for a specific layer.
  """
  def new(layer \\ :default, order \\ 0) do
    %__MODULE__{
      render_layer: layer,
      render_order: order
    }
  end
  
  @doc """
  Show the entity.
  """
  def show(%__MODULE__{} = visibility) do
    %__MODULE__{visibility | visible: true}
  end
  
  @doc """
  Hide the entity.
  """
  def hide(%__MODULE__{} = visibility) do
    %__MODULE__{visibility | visible: false}
  end
  
  @doc """
  Toggle visibility.
  """
  def toggle(%__MODULE__{} = visibility) do
    %__MODULE__{visibility | visible: not visibility.visible}
  end
  
  @doc """
  Set render layer and order.
  """
  def set_layer(%__MODULE__{} = visibility, layer, order \\ nil) do
    %__MODULE__{visibility | 
      render_layer: layer,
      render_order: order || visibility.render_order
    }
  end
  
  @doc """
  Check if should be culled based on distance.
  """
  def should_cull?(%__MODULE__{always_render: true}, _distance), do: false
  def should_cull?(%__MODULE__{visible: false}, _distance), do: true
  def should_cull?(%__MODULE__{cull_distance: nil}, _distance), do: false
  def should_cull?(%__MODULE__{cull_distance: max_dist}, distance) do
    distance > max_dist
  end
  
  @doc """
  Check if entity should be rendered.
  """
  def should_render?(%__MODULE__{visible: false, always_render: false}), do: false
  def should_render?(%__MODULE__{}), do: true
end