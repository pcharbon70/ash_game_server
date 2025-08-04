defmodule AshGameServer.Components.Rendering.Animation do
  @moduledoc """
  Animation component for frame-based sprite animations.
  
  Manages animation states, frame sequences, and playback control.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type animation_name :: atom()
  @type frame :: %{
    index: non_neg_integer(),
    duration: pos_integer()  # milliseconds
  }
  
  @type animation_def :: %{
    frames: [frame()],
    loop: boolean(),
    speed: float()
  }
  
  @type t :: %__MODULE__{
    animations: %{animation_name() => animation_def()},
    current_animation: animation_name() | nil,
    current_frame: non_neg_integer(),
    frame_time: non_neg_integer(),
    playing: boolean(),
    finished: boolean()
  }
  
  defstruct [
    animations: %{},
    current_animation: nil,
    current_frame: 0,
    frame_time: 0,
    playing: false,
    finished: false
  ]
  
  @impl true
  def validate(%__MODULE__{} = animation) do
    cond do
      not is_map(animation.animations) ->
        {:error, "Animations must be a map"}
      
      not valid_animations?(animation.animations) ->
        {:error, "Invalid animation definitions"}
      
      animation.current_frame < 0 ->
        {:error, "Current frame cannot be negative"}
      
      animation.frame_time < 0 ->
        {:error, "Frame time cannot be negative"}
      
      true ->
        :ok
    end
  end
  
  defp valid_animations?(animations) do
    Enum.all?(animations, fn {_name, def} ->
      is_map(def) and
      is_list(Map.get(def, :frames, [])) and
      is_boolean(Map.get(def, :loop, false)) and
      is_number(Map.get(def, :speed, 1.0)) and
      Map.get(def, :speed, 1.0) > 0
    end)
  end
  
  @impl true
  def serialize(%__MODULE__{} = animation) do
    %{
      animations: animation.animations,
      current_animation: animation.current_animation,
      current_frame: animation.current_frame,
      frame_time: animation.frame_time,
      playing: animation.playing,
      finished: animation.finished
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      animations: Map.get(data, :animations, %{}),
      current_animation: Map.get(data, :current_animation),
      current_frame: Map.get(data, :current_frame, 0),
      frame_time: Map.get(data, :frame_time, 0),
      playing: Map.get(data, :playing, false),
      finished: Map.get(data, :finished, false)
    }}
  end
  
  # Helper functions
  
  @doc """
  Create an animation component with definitions.
  """
  def new(animations \\ %{}) do
    %__MODULE__{animations: animations}
  end
  
  @doc """
  Add an animation definition.
  """
  def add_animation(%__MODULE__{} = anim, name, frames, loop \\ false, speed \\ 1.0) do
    animation_def = %{
      frames: normalize_frames(frames),
      loop: loop,
      speed: speed
    }
    
    %__MODULE__{anim | 
      animations: Map.put(anim.animations, name, animation_def)
    }
  end
  
  defp normalize_frames(frames) when is_list(frames) do
    Enum.map(frames, fn
      %{index: _, duration: _} = frame -> frame
      index when is_integer(index) -> %{index: index, duration: 100}
    end)
  end
  
  @doc """
  Play an animation by name.
  """
  def play(%__MODULE__{} = anim, animation_name) do
    if Map.has_key?(anim.animations, animation_name) do
      %__MODULE__{anim |
        current_animation: animation_name,
        current_frame: 0,
        frame_time: 0,
        playing: true,
        finished: false
      }
    else
      anim
    end
  end
  
  @doc """
  Stop the current animation.
  """
  def stop(%__MODULE__{} = anim) do
    %__MODULE__{anim | playing: false}
  end
  
  @doc """
  Resume a paused animation.
  """
  def resume(%__MODULE__{} = anim) do
    %__MODULE__{anim | playing: true}
  end
  
  @doc """
  Update animation state with delta time.
  """
  def update(%__MODULE__{playing: false} = anim, _delta_ms), do: anim
  def update(%__MODULE__{current_animation: nil} = anim, _delta_ms), do: anim
  def update(%__MODULE__{finished: true} = anim, _delta_ms), do: anim
  
  def update(%__MODULE__{} = anim, delta_ms) do
    case Map.get(anim.animations, anim.current_animation) do
      nil -> 
        anim
      
      animation_def ->
        update_animation(anim, animation_def, delta_ms)
    end
  end
  
  defp update_animation(anim, animation_def, delta_ms) do
    frames = animation_def.frames
    speed = animation_def.speed
    
    if frames == [] do
      anim
    else
      current_frame_def = Enum.at(frames, anim.current_frame)
      new_frame_time = anim.frame_time + round(delta_ms * speed)
      
      if new_frame_time >= current_frame_def.duration do
        advance_frame(anim, animation_def)
      else
        %__MODULE__{anim | frame_time: new_frame_time}
      end
    end
  end
  
  defp advance_frame(anim, animation_def) do
    frames = animation_def.frames
    next_frame = anim.current_frame + 1
    
    cond do
      next_frame >= length(frames) and animation_def.loop ->
        %__MODULE__{anim | current_frame: 0, frame_time: 0}
      
      next_frame >= length(frames) ->
        %__MODULE__{anim | finished: true, playing: false}
      
      true ->
        %__MODULE__{anim | current_frame: next_frame, frame_time: 0}
    end
  end
  
  @doc """
  Get the current frame index for rendering.
  """
  def get_current_frame_index(%__MODULE__{} = anim) do
    case Map.get(anim.animations, anim.current_animation) do
      nil -> 
        0
      
      animation_def ->
        frame = Enum.at(animation_def.frames, anim.current_frame)
        if frame, do: frame.index, else: 0
    end
  end
  
  @doc """
  Check if animation is playing.
  """
  def playing?(%__MODULE__{playing: playing}), do: playing
  
  @doc """
  Check if animation is finished.
  """
  def finished?(%__MODULE__{finished: finished}), do: finished
end