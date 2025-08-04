defmodule AshGameServer.Components.Network.PredictionState do
  @moduledoc """
  PredictionState component for client-side prediction and reconciliation.
  
  Tracks predicted state vs authoritative state for lag compensation
  and smooth gameplay experience.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  alias AshGameServer.Components.Transform.{Position, Velocity}
  
  @type t :: %__MODULE__{
    network_id: String.t(),
    predicted_position: Position.t() | nil,
    predicted_velocity: Velocity.t() | nil,
    predicted_rotation: float() | nil,
    authoritative_position: Position.t() | nil,
    authoritative_velocity: Velocity.t() | nil,
    prediction_errors: integer(),
    last_correction_tick: integer(),
    correction_threshold: float(),
    smoothing_enabled: boolean(),
    smoothing_factor: float(),
    input_buffer: [input_command()],
    max_input_buffer: integer()
  }
  
  @type input_command :: %{
    tick: integer(),
    command_type: atom(),
    data: map(),
    timestamp: integer()
  }
  
  defstruct [
    network_id: "",
    predicted_position: nil,
    predicted_velocity: nil,
    predicted_rotation: nil,
    authoritative_position: nil,
    authoritative_velocity: nil,
    prediction_errors: 0,
    last_correction_tick: 0,
    correction_threshold: 1.0,
    smoothing_enabled: true,
    smoothing_factor: 0.1,
    input_buffer: [],
    max_input_buffer: 60  # 1 second at 60fps
  ]
  
  @impl true
  def validate(%__MODULE__{} = pred_state) do
    with :ok <- validate_network_id(pred_state),
         :ok <- validate_thresholds(pred_state),
         :ok <- validate_buffer_size(pred_state) do
    end
  end
  
  defp validate_network_id(%__MODULE__{network_id: id}) when id == "" do
    {:error, "Network ID cannot be empty"}
  end
  defp validate_network_id(_pred_state), do: :ok
  
  defp validate_thresholds(%__MODULE__{correction_threshold: threshold, smoothing_factor: factor}) do
    cond do
      threshold < 0.0 -> {:error, "Correction threshold cannot be negative"}
      factor < 0.0 or factor > 1.0 -> {:error, "Smoothing factor must be between 0.0 and 1.0"}
      true -> :ok
    end
  end
  
  defp validate_buffer_size(%__MODULE__{max_input_buffer: size}) when size <= 0 do
    {:error, "Max input buffer must be positive"}
  end
  defp validate_buffer_size(_pred_state), do: :ok
  
  @impl true
  def serialize(%__MODULE__{} = pred_state) do
    %{
      network_id: pred_state.network_id,
      predicted_position: serialize_position(pred_state.predicted_position),
      predicted_velocity: serialize_velocity(pred_state.predicted_velocity),
      predicted_rotation: pred_state.predicted_rotation,
      authoritative_position: serialize_position(pred_state.authoritative_position),
      authoritative_velocity: serialize_velocity(pred_state.authoritative_velocity),
      prediction_errors: pred_state.prediction_errors,
      last_correction_tick: pred_state.last_correction_tick,
      correction_threshold: Float.round(pred_state.correction_threshold * 1.0, 2),
      smoothing_enabled: pred_state.smoothing_enabled,
      smoothing_factor: Float.round(pred_state.smoothing_factor * 1.0, 3),
      input_buffer: serialize_input_buffer(pred_state.input_buffer),
      max_input_buffer: pred_state.max_input_buffer
    }
  end
  
  defp serialize_position(nil), do: nil
  defp serialize_position(%Position{} = pos) do
    %{
      x: Float.round(pos.x * 1.0, 2),
      y: Float.round(pos.y * 1.0, 2),
      z: Float.round(pos.z * 1.0, 2)
    }
  end
  
  defp serialize_velocity(nil), do: nil
  defp serialize_velocity(%Velocity{} = vel) do
    %{
      linear_x: Float.round(vel.linear_x * 1.0, 2),
      linear_y: Float.round(vel.linear_y * 1.0, 2),
      linear_z: Float.round(vel.linear_z * 1.0, 2)
    }
  end
  
  defp serialize_input_buffer(buffer) do
    Enum.map(buffer, fn command ->
      %{
        tick: command.tick,
        command_type: command.command_type,
        data: command.data,
        timestamp: command.timestamp
      }
    end)
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      network_id: Map.get(data, :network_id, ""),
      predicted_position: deserialize_position(Map.get(data, :predicted_position)),
      predicted_velocity: deserialize_velocity(Map.get(data, :predicted_velocity)),
      predicted_rotation: Map.get(data, :predicted_rotation),
      authoritative_position: deserialize_position(Map.get(data, :authoritative_position)),
      authoritative_velocity: deserialize_velocity(Map.get(data, :authoritative_velocity)),
      prediction_errors: Map.get(data, :prediction_errors, 0),
      last_correction_tick: Map.get(data, :last_correction_tick, 0),
      correction_threshold: max(Map.get(data, :correction_threshold, 1.0) * 1.0, 0.0),
      smoothing_enabled: Map.get(data, :smoothing_enabled, true),
      smoothing_factor: clamp(Map.get(data, :smoothing_factor, 0.1) * 1.0, 0.0, 1.0),
      input_buffer: deserialize_input_buffer(Map.get(data, :input_buffer, [])),
      max_input_buffer: max(Map.get(data, :max_input_buffer, 60), 1)
    }}
  end
  
  defp deserialize_position(nil), do: nil
  defp deserialize_position(data) when is_map(data) do
    %Position{
      x: Map.get(data, :x, 0.0) * 1.0,
      y: Map.get(data, :y, 0.0) * 1.0,
      z: Map.get(data, :z, 0.0) * 1.0
    }
  end
  
  defp deserialize_velocity(nil), do: nil
  defp deserialize_velocity(data) when is_map(data) do
    %Velocity{
      linear_x: Map.get(data, :linear_x, 0.0) * 1.0,
      linear_y: Map.get(data, :linear_y, 0.0) * 1.0,
      linear_z: Map.get(data, :linear_z, 0.0) * 1.0
    }
  end
  
  defp deserialize_input_buffer(buffer) when is_list(buffer) do
    Enum.map(buffer, fn command ->
      %{
        tick: Map.get(command, :tick, 0),
        command_type: Map.get(command, :command_type, :move),
        data: Map.get(command, :data, %{}),
        timestamp: Map.get(command, :timestamp, 0)
      }
    end)
  end
  defp deserialize_input_buffer(_), do: []
  
  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
  defp clamp(_value, _min, max), do: max
  
  # Helper functions
  
  @doc """
  Create prediction state for a networked entity.
  """
  def new(network_id) do
    %__MODULE__{network_id: network_id}
  end
  
  @doc """
  Update predicted state based on input.
  """
  def update_prediction(%__MODULE__{} = pred_state, position, velocity, rotation \\ nil) do
    %__MODULE__{pred_state |
      predicted_position: position,
      predicted_velocity: velocity,
      predicted_rotation: rotation
    }
  end
  
  @doc """
  Set authoritative state from server.
  """
  def set_authoritative_state(%__MODULE__{} = pred_state, position, velocity \\ nil) do
    %__MODULE__{pred_state |
      authoritative_position: position,
      authoritative_velocity: velocity
    }
  end
  
  @doc """
  Check if prediction correction is needed.
  """
  def needs_correction?(%__MODULE__{} = pred_state) do
    case {pred_state.predicted_position, pred_state.authoritative_position} do
      {%Position{} = pred, %Position{} = auth} ->
        error = Position.distance(pred, auth)
        error > pred_state.correction_threshold
      
      _ -> false
    end
  end
  
  @doc """
  Apply correction with smoothing if enabled.
  """
  def apply_correction(%__MODULE__{} = pred_state, tick) do
    case {pred_state.predicted_position, pred_state.authoritative_position} do
      {%Position{} = pred, %Position{} = auth} ->
        corrected_position = if pred_state.smoothing_enabled do
          smooth_interpolate(pred, auth, pred_state.smoothing_factor)
        else
          auth
        end
        
        %__MODULE__{pred_state |
          predicted_position: corrected_position,
          prediction_errors: pred_state.prediction_errors + 1,
          last_correction_tick: tick
        }
      
      _ -> pred_state
    end
  end
  
  defp smooth_interpolate(%Position{} = from, %Position{} = to, factor) do
    %Position{
      x: from.x + (to.x - from.x) * factor,
      y: from.y + (to.y - from.y) * factor,
      z: from.z + (to.z - from.z) * factor
    }
  end
  
  @doc """
  Add input command to buffer.
  """
  def add_input(%__MODULE__{} = pred_state, tick, command_type, data) do
    command = %{
      tick: tick,
      command_type: command_type,
      data: data,
      timestamp: System.monotonic_time()
    }
    
    # Add to buffer and maintain size limit
    updated_buffer = [command | pred_state.input_buffer]
    |> Enum.take(pred_state.max_input_buffer)
    
    %__MODULE__{pred_state | input_buffer: updated_buffer}
  end
  
  @doc """
  Remove input commands older than specified tick.
  """
  def trim_input_buffer(%__MODULE__{} = pred_state, oldest_tick) do
    updated_buffer = Enum.filter(pred_state.input_buffer, fn command ->
      command.tick >= oldest_tick
    end)
    
    %__MODULE__{pred_state | input_buffer: updated_buffer}
  end
  
  @doc """
  Get input commands for a specific tick range.
  """
  def get_inputs_for_range(%__MODULE__{} = pred_state, start_tick, end_tick) do
    Enum.filter(pred_state.input_buffer, fn command ->
      command.tick >= start_tick and command.tick <= end_tick
    end)
    |> Enum.sort_by(fn command -> command.tick end)
  end
  
  @doc """
  Calculate prediction accuracy as a percentage.
  """
  def get_prediction_accuracy(%__MODULE__{} = pred_state) do
    if pred_state.prediction_errors == 0 do
      100.0
    else
      total_predictions = pred_state.prediction_errors + 100  # Assume some successful predictions
      accuracy = (total_predictions - pred_state.prediction_errors) / total_predictions * 100.0
      max(0.0, accuracy)
    end
  end
  
  @doc """
  Reset prediction statistics.
  """
  def reset_stats(%__MODULE__{} = pred_state) do
    %__MODULE__{pred_state |
      prediction_errors: 0,
      last_correction_tick: 0
    }
  end
  
  @doc """
  Set correction sensitivity.
  """
  def set_correction_threshold(%__MODULE__{} = pred_state, threshold) when threshold >= 0 do
    %__MODULE__{pred_state | correction_threshold: threshold}
  end
  
  @doc """
  Configure smoothing settings.
  """
  def set_smoothing(%__MODULE__{} = pred_state, enabled, factor \\ 0.1) do
    %__MODULE__{pred_state |
      smoothing_enabled: enabled,
      smoothing_factor: clamp(factor, 0.0, 1.0)
    }
  end
  
  @doc """
  Check if prediction state is stale (no recent updates).
  """
  def stale?(%__MODULE__{} = pred_state, current_tick, max_age \\ 120) do
    (current_tick - pred_state.last_correction_tick) > max_age
  end
end