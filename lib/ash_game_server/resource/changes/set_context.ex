defmodule AshGameServer.Resource.Changes.SetContext do
  @moduledoc """
  Change module for setting context values on resources.

  Used primarily for audit fields like created_by_id and updated_by_id.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    attribute = opts[:attribute]

    case Map.get(context, :actor) do
      nil ->
        changeset

      %{id: actor_id} ->
        Ash.Changeset.force_change_attribute(changeset, attribute, actor_id)

      _ ->
        changeset
    end
  end
end
