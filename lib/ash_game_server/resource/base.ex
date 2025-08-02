defmodule AshGameServer.Resource.Base do
  @moduledoc """
  Base resource module providing common patterns for all game resources.
  
  This module provides:
  - UUID primary key
  - Timestamps (inserted_at, updated_at)
  - Audit fields (created_by, updated_by)
  - Soft delete support
  - Common actions
  """

  defmacro __using__(opts \\ []) do
    quote location: :keep do
      use Ash.Resource,
        domain: unquote(opts[:domain]),
        data_layer: AshPostgres.DataLayer,
        notifiers: [Ash.Notifier.PubSub]

      postgres do
        repo AshGameServer.Repo
        table unquote(opts[:table]) || (__MODULE__ |> Module.split() |> List.last() |> Macro.underscore() |> Kernel.<>("s"))
      end

      # Common attributes
      attributes do
        uuid_primary_key :id
        
        # Timestamps
        create_timestamp :inserted_at
        update_timestamp :updated_at
        
        # Soft delete
        attribute :deleted_at, :utc_datetime_usec,
          allow_nil?: true,
          public?: false
        
        # Audit fields
        attribute :created_by_id, :uuid,
          allow_nil?: true,
          public?: false
        
        attribute :updated_by_id, :uuid,
          allow_nil?: true,
          public?: false
      end

      # Common actions
      actions do
        defaults [:read]
        
        create :base_create do
          accept :*
          
          change set_context(:created_by_id)
        end
        
        update :base_update do
          accept :*
          
          change set_context(:updated_by_id)
        end
        
        destroy :base_destroy do
          soft? true
          
          change set_attribute(:deleted_at, &DateTime.utc_now/0)
        end
        
        # Hard delete action
        destroy :hard_delete do
          soft? false
        end
        
        # Restore soft-deleted records
        update :restore do
          accept []
          
          change set_attribute(:deleted_at, nil)
        end
      end

      # Common preparations
      preparations do
        prepare build(load: [:created_by, :updated_by])
        # Automatically filter out soft-deleted records on read
        prepare build(filter: [is_nil: :deleted_at]), on: [:read]
      end

      # Default PubSub configuration
      pub_sub do
        module AshGameServer.PubSubHelper
        prefix unquote(opts[:pub_sub_prefix]) || (__MODULE__ |> Module.split() |> List.last() |> Macro.underscore())
        
        publish_all :create, "created"
        publish_all :update, "updated"
        publish_all :destroy, "deleted"
      end

      # Helper functions

      defp set_context(attribute) do
        {AshGameServer.Resource.Changes.SetContext, attribute: attribute}
      end
    end
  end
end