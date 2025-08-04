defmodule AshGameServer.Components.AI.Perception do
  @moduledoc """
  Perception component for AI sensory awareness.
  
  Manages detection ranges, visible entities, and threat assessment.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type perception_type :: :visual | :audio | :proximity
  
  @type detected_entity :: %{
    id: String.t(),
    type: perception_type(),
    distance: float(),
    last_seen: float(),
    threat_level: float()
  }
  
  @type t :: %__MODULE__{
    sight_range: float(),
    hearing_range: float(),
    proximity_range: float(),
    field_of_view: float(),  # degrees
    detected_entities: %{String.t() => detected_entity()},
    max_tracked: pos_integer(),
    forget_time: float(),  # milliseconds
    alert_level: float()  # 0.0 to 1.0
  }
  
  defstruct [
    sight_range: 100.0,
    hearing_range: 150.0,
    proximity_range: 20.0,
    field_of_view: 120.0,
    detected_entities: %{},
    max_tracked: 10,
    forget_time: 5000.0,
    alert_level: 0.0
  ]
  
  @impl true
  def validate(%__MODULE__{} = perception) do
    cond do
      perception.sight_range < 0 ->
        {:error, "Sight range cannot be negative"}
      
      perception.hearing_range < 0 ->
        {:error, "Hearing range cannot be negative"}
      
      perception.proximity_range < 0 ->
        {:error, "Proximity range cannot be negative"}
      
      perception.field_of_view < 0 or perception.field_of_view > 360 ->
        {:error, "Field of view must be between 0 and 360 degrees"}
      
      perception.max_tracked <= 0 ->
        {:error, "Max tracked entities must be positive"}
      
      perception.forget_time < 0 ->
        {:error, "Forget time cannot be negative"}
      
      perception.alert_level < 0 or perception.alert_level > 1 ->
        {:error, "Alert level must be between 0 and 1"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = perception) do
    %{
      sight_range: Float.round(perception.sight_range * 1.0, 1),
      hearing_range: Float.round(perception.hearing_range * 1.0, 1),
      proximity_range: Float.round(perception.proximity_range * 1.0, 1),
      field_of_view: Float.round(perception.field_of_view * 1.0, 1),
      detected_entities: serialize_entities(perception.detected_entities),
      max_tracked: perception.max_tracked,
      forget_time: Float.round(perception.forget_time * 1.0, 1),
      alert_level: Float.round(perception.alert_level * 1.0, 3)
    }
  end
  
  defp serialize_entities(entities) do
    Map.new(entities, fn {id, entity} ->
      {id, %{
        id: entity.id,
        type: entity.type,
        distance: Float.round(entity.distance * 1.0, 1),
        last_seen: Float.round(entity.last_seen * 1.0, 1),
        threat_level: Float.round(entity.threat_level * 1.0, 2)
      }}
    end)
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      sight_range: Map.get(data, :sight_range, 100.0) * 1.0,
      hearing_range: Map.get(data, :hearing_range, 150.0) * 1.0,
      proximity_range: Map.get(data, :proximity_range, 20.0) * 1.0,
      field_of_view: Map.get(data, :field_of_view, 120.0) * 1.0,
      detected_entities: deserialize_entities(Map.get(data, :detected_entities, %{})),
      max_tracked: Map.get(data, :max_tracked, 10),
      forget_time: Map.get(data, :forget_time, 5000.0) * 1.0,
      alert_level: clamp(Map.get(data, :alert_level, 0.0), 0.0, 1.0)
    }}
  end
  
  defp deserialize_entities(entities) do
    Map.new(entities, fn {id, entity} ->
      {id, %{
        id: Map.get(entity, :id, id),
        type: Map.get(entity, :type, :visual),
        distance: Map.get(entity, :distance, 0.0) * 1.0,
        last_seen: Map.get(entity, :last_seen, 0.0) * 1.0,
        threat_level: Map.get(entity, :threat_level, 0.0) * 1.0
      }}
    end)
  end
  
  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
  defp clamp(_value, _min, default), do: default
  
  # Helper functions
  
  @doc """
  Create perception with custom ranges.
  """
  def new(sight \\ 100.0, hearing \\ 150.0, proximity \\ 20.0) do
    %__MODULE__{
      sight_range: sight,
      hearing_range: hearing,
      proximity_range: proximity
    }
  end
  
  @doc """
  Detect an entity.
  """
  def detect_entity(%__MODULE__{} = perception, entity_id, distance, type \\ :visual, threat \\ 0.5) do
    if map_size(perception.detected_entities) >= perception.max_tracked do
      # Remove oldest detection if at max
      oldest = perception.detected_entities
      |> Enum.min_by(fn {_id, e} -> e.last_seen end, fn -> {nil, %{last_seen: 0}} end)
      |> elem(0)
      
      detect_after_remove(perception, oldest, entity_id, distance, type, threat)
    else
      add_detection(perception, entity_id, distance, type, threat)
    end
  end
  
  defp detect_after_remove(perception, nil, entity_id, distance, type, threat) do
    add_detection(perception, entity_id, distance, type, threat)
  end
  
  defp detect_after_remove(perception, oldest_id, entity_id, distance, type, threat) do
    perception
    |> forget_entity(oldest_id)
    |> add_detection(entity_id, distance, type, threat)
  end
  
  defp add_detection(perception, entity_id, distance, type, threat) do
    entity = %{
      id: entity_id,
      type: type,
      distance: distance,
      last_seen: 0.0,
      threat_level: threat
    }
    
    %__MODULE__{perception |
      detected_entities: Map.put(perception.detected_entities, entity_id, entity)
    }
  end
  
  @doc """
  Forget an entity.
  """
  def forget_entity(%__MODULE__{} = perception, entity_id) do
    %__MODULE__{perception |
      detected_entities: Map.delete(perception.detected_entities, entity_id)
    }
  end
  
  @doc """
  Update perception with time delta, forgetting old detections.
  """
  def update(%__MODULE__{} = perception, delta_ms) do
    updated_entities = perception.detected_entities
    |> Enum.map(fn {id, entity} ->
      {id, %{entity | last_seen: entity.last_seen + delta_ms}}
    end)
    |> Enum.filter(fn {_id, entity} ->
      entity.last_seen < perception.forget_time
    end)
    |> Map.new()
    
    # Update alert level based on threats
    alert = calculate_alert_level(updated_entities)
    
    %__MODULE__{perception |
      detected_entities: updated_entities,
      alert_level: alert
    }
  end
  
  defp calculate_alert_level(entities) when map_size(entities) == 0, do: 0.0
  defp calculate_alert_level(entities) do
    max_threat = entities
    |> Enum.map(fn {_id, e} -> e.threat_level end)
    |> Enum.max(fn -> 0.0 end)
    
    clamp(max_threat, 0.0, 1.0)
  end
  
  @doc """
  Get closest detected entity.
  """
  def get_closest(%__MODULE__{detected_entities: entities}) when map_size(entities) == 0, do: nil
  def get_closest(%__MODULE__{detected_entities: entities}) do
    entities
    |> Enum.min_by(fn {_id, e} -> e.distance end)
    |> elem(1)
  end
  
  @doc """
  Get most threatening entity.
  """
  def get_highest_threat(%__MODULE__{detected_entities: entities}) when map_size(entities) == 0, do: nil
  def get_highest_threat(%__MODULE__{detected_entities: entities}) do
    entities
    |> Enum.max_by(fn {_id, e} -> e.threat_level end)
    |> elem(1)
  end
  
  @doc """
  Check if any threats detected.
  """
  def has_threats?(%__MODULE__{} = perception) do
    Enum.any?(perception.detected_entities, fn {_id, e} ->
      e.threat_level > 0.5
    end)
  end
  
  @doc """
  Check if entity is in sight range.
  """
  def in_sight_range?(%__MODULE__{sight_range: range}, distance) do
    distance <= range
  end
  
  @doc """
  Check if entity is in hearing range.
  """
  def in_hearing_range?(%__MODULE__{hearing_range: range}, distance) do
    distance <= range
  end
end