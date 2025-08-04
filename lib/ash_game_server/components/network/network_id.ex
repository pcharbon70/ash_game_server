defmodule AshGameServer.Components.Network.NetworkID do
  @moduledoc """
  Network ID component for entity identification across the network.
  
  Provides unique identification for network synchronization.
  """
  
  use AshGameServer.ECS.ComponentBehaviour
  
  @type t :: %__MODULE__{
    id: String.t(),
    owner_id: String.t() | nil,
    authority: :server | :client,
    last_sync: integer() | nil
  }
  
  defstruct [
    id: "",
    owner_id: nil,
    authority: :server,
    last_sync: nil
  ]
  
  @impl true
  def validate(%__MODULE__{} = network_id) do
    cond do
      network_id.id == "" ->
        {:error, "NetworkID cannot be empty"}
      
      network_id.authority not in [:server, :client] ->
        {:error, "Authority must be :server or :client"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(%__MODULE__{} = network_id) do
    %{
      id: network_id.id,
      owner_id: network_id.owner_id,
      authority: network_id.authority,
      last_sync: network_id.last_sync
    }
  end
  
  @impl true
  def deserialize(data) when is_map(data) do
    {:ok, %__MODULE__{
      id: Map.get(data, :id, ""),
      owner_id: Map.get(data, :owner_id),
      authority: Map.get(data, :authority, :server),
      last_sync: Map.get(data, :last_sync)
    }}
  end
  
  # Helper functions
  
  @doc """
  Generate a new network ID.
  """
  def generate(prefix \\ "net") do
    timestamp = System.os_time(:microsecond)
    random = :rand.uniform(999_999)
    "#{prefix}_#{timestamp}_#{random}"
  end
  
  @doc """
  Create a new NetworkID component.
  """
  def new(owner_id \\ nil) do
    %__MODULE__{
      id: generate(),
      owner_id: owner_id,
      authority: if(owner_id, do: :client, else: :server),
      last_sync: System.monotonic_time(:millisecond)
    }
  end
  
  @doc """
  Update sync timestamp.
  """
  def mark_synced(%__MODULE__{} = network_id) do
    %__MODULE__{network_id | last_sync: System.monotonic_time(:millisecond)}
  end
  
  @doc """
  Check if needs sync based on time threshold.
  """
  def needs_sync?(%__MODULE__{last_sync: nil}, _threshold), do: true
  def needs_sync?(%__MODULE__{last_sync: last}, threshold_ms) do
    current = System.monotonic_time(:millisecond)
    current - last > threshold_ms
  end
end