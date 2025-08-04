defmodule AshGameServer.Actions.ProcessMessage do
  @moduledoc """
  Action for processing incoming messages in agents.
  """
  use Jido.Action,
    name: "process_message",
    description: "Processes an incoming message with validation",
    schema: [
      message: [type: :string, required: true],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _context) do
    # Validate message
    with {:ok, cleaned_message} <- clean_message(params.message),
         {:ok, processed_data} <- process_content(cleaned_message, params.metadata) do

      result = %{
        processed_message: processed_data,
        original_length: String.length(params.message),
        processed_at: DateTime.utc_now(),
        success: true
      }

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp clean_message(message) when is_binary(message) do
    cleaned = String.trim(message)

    if String.length(cleaned) > 0 do
      {:ok, cleaned}
    else
      {:error, :empty_message}
    end
  end
  defp clean_message(_), do: {:error, :invalid_message_type}

  defp process_content(message, metadata) do
    # Simple processing - could be expanded for actual game logic
    processed = %{
      content: message,
      word_count: length(String.split(message)),
      processed_with: metadata,
      hash: :crypto.hash(:sha256, message) |> Base.encode16(case: :lower)
    }

    {:ok, processed}
  end
end
