defmodule AshGameServer.Components.Gameplay.Health do
  @moduledoc """
  Health component for entity vitality and damage tracking.

  Tracks current and maximum health points, regeneration, and damage resistance.
  Emits events when health changes or entity dies.
  """

  use AshGameServer.ECS.ComponentBehaviour

  @type t :: %__MODULE__{
    current: float(),
    maximum: float(),
    regeneration_rate: float(),  # HP per second
    damage_resistance: float(),   # 0.0 = no resistance, 1.0 = immune
    is_invulnerable: boolean(),
    last_damage_time: integer() | nil,
    last_damage_source: term() | nil
  }

  defstruct [
    current: 100.0,
    maximum: 100.0,
    regeneration_rate: 0.0,
    damage_resistance: 0.0,
    is_invulnerable: false,
    last_damage_time: nil,
    last_damage_source: nil
  ]

  @impl true
  def validate(%__MODULE__{} = health) do
    with :ok <- validate_health_values(health),
         :ok <- validate_regeneration(health),
         :ok <- validate_resistance(health) do
      validate_invulnerability(health)
    end
  end

  # Private validation helpers

  defp validate_health_values(%__MODULE__{current: current, maximum: maximum}) do
    cond do
      not is_number(current) ->
        {:error, "Health current must be a number"}

      not is_number(maximum) ->
        {:error, "Health maximum must be a number"}

      maximum <= 0 ->
        {:error, "Health maximum must be positive"}

      current < 0 ->
        {:error, "Health current cannot be negative"}

      current > maximum ->
        {:error, "Health current cannot exceed maximum"}

      true ->
        :ok
    end
  end

  defp validate_regeneration(%__MODULE__{regeneration_rate: rate}) do
    if is_number(rate) do
      :ok
    else
      {:error, "Health regeneration_rate must be a number"}
    end
  end

  defp validate_resistance(%__MODULE__{damage_resistance: resistance}) do
    cond do
      not is_number(resistance) ->
        {:error, "Health damage_resistance must be a number"}

      resistance < 0 or resistance > 1 ->
        {:error, "Health damage_resistance must be between 0 and 1"}

      true ->
        :ok
    end
  end

  defp validate_invulnerability(%__MODULE__{is_invulnerable: invulnerable}) do
    if is_boolean(invulnerable) do
      :ok
    else
      {:error, "Health is_invulnerable must be a boolean"}
    end
  end

  @impl true
  def serialize(%__MODULE__{} = health) do
    %{
      current: Float.round(health.current * 1.0, 2),
      maximum: Float.round(health.maximum * 1.0, 2),
      regeneration_rate: Float.round(health.regeneration_rate * 1.0, 2),
      damage_resistance: Float.round(health.damage_resistance * 1.0, 3),
      is_invulnerable: health.is_invulnerable,
      last_damage_time: health.last_damage_time,
      last_damage_source: health.last_damage_source
    }
  end

  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      current: Map.get(data, :current, 100.0) * 1.0,
      maximum: Map.get(data, :maximum, 100.0) * 1.0,
      regeneration_rate: Map.get(data, :regeneration_rate, 0.0) * 1.0,
      damage_resistance: Map.get(data, :damage_resistance, 0.0) * 1.0,
      is_invulnerable: Map.get(data, :is_invulnerable, false),
      last_damage_time: Map.get(data, :last_damage_time),
      last_damage_source: Map.get(data, :last_damage_source)
    }}
  end

  # Helper functions

  @doc """
  Create a new health component with specified maximum health.
  """
  def new(max_health) when is_number(max_health) and max_health > 0 do
    %__MODULE__{
      current: max_health * 1.0,
      maximum: max_health * 1.0
    }
  end

  @doc """
  Apply damage to health, respecting resistance and invulnerability.
  """
  def take_damage(%__MODULE__{} = health, amount, source \\ nil) when is_number(amount) do
    cond do
      health.is_invulnerable ->
        health

      amount <= 0 ->
        health

      true ->
        # Apply damage resistance
        actual_damage = amount * (1.0 - health.damage_resistance)
        new_current = max(0.0, health.current - actual_damage)

        %__MODULE__{health |
          current: new_current,
          last_damage_time: System.monotonic_time(:millisecond),
          last_damage_source: source
        }
    end
  end

  @doc """
  Heal health by specified amount, not exceeding maximum.
  """
  def heal(%__MODULE__{} = health, amount) when is_number(amount) and amount > 0 do
    new_current = min(health.maximum, health.current + amount)
    %__MODULE__{health | current: new_current}
  end

  @doc """
  Apply regeneration over time delta.
  """
  def regenerate(%__MODULE__{} = health, delta_time) when is_number(delta_time) do
    if health.regeneration_rate > 0 and health.current < health.maximum do
      heal_amount = health.regeneration_rate * delta_time
      heal(health, heal_amount)
    else
      health
    end
  end

  @doc """
  Set health to full.
  """
  def restore_full(%__MODULE__{} = health) do
    %__MODULE__{health | current: health.maximum}
  end

  @doc """
  Check if entity is dead (health <= 0).
  """
  def dead?(%__MODULE__{current: current}), do: current <= 0

  @doc """
  Check if entity is alive (health > 0).
  """
  def alive?(%__MODULE__{} = health), do: not dead?(health)

  @doc """
  Check if health is full.
  """
  def full?(%__MODULE__{current: current, maximum: maximum}), do: current >= maximum

  @doc """
  Get health percentage (0.0 to 1.0).
  """
  def percentage(%__MODULE__{current: current, maximum: maximum}) do
    if maximum > 0, do: current / maximum, else: 0.0
  end

  @doc """
  Get missing health amount.
  """
  def missing(%__MODULE__{current: current, maximum: maximum}) do
    max(0.0, maximum - current)
  end

  @doc """
  Set invulnerability status.
  """
  def set_invulnerable(%__MODULE__{} = health, invulnerable) when is_boolean(invulnerable) do
    %__MODULE__{health | is_invulnerable: invulnerable}
  end

  @doc """
  Set damage resistance (0.0 to 1.0).
  """
  def set_resistance(%__MODULE__{} = health, resistance) when is_number(resistance) do
    clamped = max(0.0, min(1.0, resistance))
    %__MODULE__{health | damage_resistance: clamped}
  end

  @doc """
  Modify maximum health, scaling current health proportionally.
  """
  def set_maximum(%__MODULE__{} = health, new_max, scale_current \\ true)
      when is_number(new_max) and new_max > 0 do
    if scale_current and health.maximum > 0 do
      ratio = health.current / health.maximum
      %__MODULE__{health |
        maximum: new_max,
        current: new_max * ratio
      }
    else
      %__MODULE__{health |
        maximum: new_max,
        current: min(health.current, new_max)
      }
    end
  end

  @doc """
  Check if health changed recently (within threshold milliseconds).
  """
  def recently_damaged?(%__MODULE__{last_damage_time: nil}, _threshold), do: false
  def recently_damaged?(%__MODULE__{last_damage_time: time}, threshold) do
    current_time = System.monotonic_time(:millisecond)
    current_time - time < threshold
  end
end
