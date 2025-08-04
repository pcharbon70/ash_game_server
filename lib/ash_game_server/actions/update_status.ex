defmodule AshGameServer.Actions.UpdateStatus do
  @moduledoc """
  Action for updating agent status with validation.
  """
  use Jido.Action,
    name: "update_status",
    description: "Updates agent status with transition validation",
    schema: [
      new_status: [type: :atom, required: true],
      current_status: [type: :atom, required: true],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, _} <- validate_transition(params.current_status, params.new_status),
         {:ok, _update_result} <- apply_status_update(params) do

      result = %{
        previous_status: params.current_status,
        new_status: params.new_status,
        updated_at: DateTime.utc_now(),
        metadata: params.metadata,
        success: true
      }

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp validate_transition(from, to) do
    valid_transitions = %{
      :idle => [:active, :processing, :stopped],
      :active => [:idle, :processing, :stopped],
      :processing => [:idle, :active, :stopped],
      :stopped => [:idle]
    }

    allowed = Map.get(valid_transitions, from, [])

    if to in allowed do
      {:ok, :valid_transition}
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  defp apply_status_update(params) do
    # Here we could add additional logic for status changes
    # like logging, notifications, cleanup, etc.

    update_info = %{
      transition: "#{params.current_status} -> #{params.new_status}",
      applied_at: DateTime.utc_now(),
      metadata: params.metadata
    }

    {:ok, update_info}
  end
end
