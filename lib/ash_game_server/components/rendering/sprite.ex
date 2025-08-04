defmodule AshGameServer.Components.Rendering.Sprite do
  @moduledoc """
  Sprite component for 2D texture rendering.
  
  Manages texture references, rendering properties, and sprite sheets.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    texture_id: String.t(),
    width: pos_integer(),
    height: pos_integer(),
    source_rect: rect() | nil,
    tint: color(),
    flip_x: boolean(),
    flip_y: boolean(),
    opacity: float(),
    blend_mode: blend_mode()
  }
  
  @type rect :: %{x: integer(), y: integer(), width: pos_integer(), height: pos_integer()}
  @type color :: %{r: integer(), g: integer(), b: integer(), a: integer()}
  @type blend_mode :: :normal | :additive | :multiply | :screen
  
  defstruct [
    texture_id: "",
    width: 32,
    height: 32,
    source_rect: nil,
    tint: %{r: 255, g: 255, b: 255, a: 255},
    flip_x: false,
    flip_y: false,
    opacity: 1.0,
    blend_mode: :normal
  ]
  
  @impl true
  def validate(%__MODULE__{} = sprite) do
    cond do
      sprite.texture_id == "" ->
        {:error, "Sprite texture_id cannot be empty"}
      
      sprite.width <= 0 or sprite.height <= 0 ->
        {:error, "Sprite dimensions must be positive"}
      
      sprite.opacity < 0.0 or sprite.opacity > 1.0 ->
        {:error, "Sprite opacity must be between 0.0 and 1.0"}
      
      sprite.blend_mode not in [:normal, :additive, :multiply, :screen] ->
        {:error, "Invalid blend mode"}
      
      not valid_color?(sprite.tint) ->
        {:error, "Invalid tint color"}
      
      sprite.source_rect != nil and not valid_rect?(sprite.source_rect) ->
        {:error, "Invalid source rectangle"}
      
      true ->
        :ok
    end
  end
  
  defp valid_color?(%{r: r, g: g, b: b, a: a}) do
    Enum.all?([r, g, b, a], fn v -> 
      is_integer(v) and v >= 0 and v <= 255
    end)
  end
  defp valid_color?(_), do: false
  
  defp valid_rect?(%{x: x, y: y, width: w, height: h}) do
    is_integer(x) and is_integer(y) and w > 0 and h > 0
  end
  defp valid_rect?(_), do: false
  
  @impl true
  def serialize(%__MODULE__{} = sprite) do
    %{
      texture_id: sprite.texture_id,
      width: sprite.width,
      height: sprite.height,
      source_rect: sprite.source_rect,
      tint: sprite.tint,
      flip_x: sprite.flip_x,
      flip_y: sprite.flip_y,
      opacity: Float.round(sprite.opacity * 1.0, 3),
      blend_mode: sprite.blend_mode
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      texture_id: Map.get(data, :texture_id, ""),
      width: Map.get(data, :width, 32),
      height: Map.get(data, :height, 32),
      source_rect: Map.get(data, :source_rect),
      tint: deserialize_color(Map.get(data, :tint)),
      flip_x: Map.get(data, :flip_x, false),
      flip_y: Map.get(data, :flip_y, false),
      opacity: clamp(Map.get(data, :opacity, 1.0), 0.0, 1.0),
      blend_mode: Map.get(data, :blend_mode, :normal)
    }}
  end
  
  defp deserialize_color(nil), do: %{r: 255, g: 255, b: 255, a: 255}
  defp deserialize_color(color) when is_map(color) do
    %{
      r: clamp(Map.get(color, :r, 255), 0, 255),
      g: clamp(Map.get(color, :g, 255), 0, 255),
      b: clamp(Map.get(color, :b, 255), 0, 255),
      a: clamp(Map.get(color, :a, 255), 0, 255)
    }
  end
  
  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
  defp clamp(_value, _min, max), do: max
  
  # Helper functions
  
  @doc """
  Create a sprite from a texture.
  """
  def from_texture(texture_id, width \\ 32, height \\ 32) do
    %__MODULE__{
      texture_id: texture_id,
      width: width,
      height: height
    }
  end
  
  @doc """
  Create a sprite from a sprite sheet region.
  """
  def from_sheet(texture_id, x, y, width, height) do
    %__MODULE__{
      texture_id: texture_id,
      width: width,
      height: height,
      source_rect: %{x: x, y: y, width: width, height: height}
    }
  end
  
  @doc """
  Set sprite tint color.
  """
  def set_tint(%__MODULE__{} = sprite, r, g, b, a \\ 255) do
    %__MODULE__{sprite | tint: %{r: r, g: g, b: b, a: a}}
  end
  
  @doc """
  Set sprite opacity.
  """
  def set_opacity(%__MODULE__{} = sprite, opacity) do
    %__MODULE__{sprite | opacity: clamp(opacity, 0.0, 1.0)}
  end
  
  @doc """
  Flip sprite horizontally or vertically.
  """
  def flip(%__MODULE__{} = sprite, horizontal \\ false, vertical \\ false) do
    %__MODULE__{sprite | flip_x: horizontal, flip_y: vertical}
  end
end