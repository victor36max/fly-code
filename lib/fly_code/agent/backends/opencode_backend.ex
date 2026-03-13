defmodule FlyCode.Agent.Backends.OpenCode do
  @moduledoc """
  Backend adapter for the OpenCode SDK.

  Starts a managed OpenCode server, creates a session, and streams events
  via SSE using `event_subscribe`. All events are normalized to the same
  tagged tuple format used by the ClaudeCode backend.
  """

  require Logger

  alias OpenCode.Generated.Operations

  def start(_session_id, workspace_path, _pubsub_topic) do
    with {:ok, %{client: client, server: server}} <-
           OpenCode.create(config: %{}, hostname: "127.0.0.1"),
         client_opts <- Keyword.put(client, :directory, workspace_path),
         {:ok, session} <- Operations.session_create(%{}, client_opts) do
      {:ok,
       %{
         client: client_opts,
         server: server,
         opencode_session_id: session.id
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to start OpenCode backend: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def stream(%{client: client, opencode_session_id: sid} = _client_state, text) do
    # Subscribe to SSE events first
    {:ok, event_stream} = Operations.event_subscribe(client)

    # Kick off the async prompt so events stream in
    :ok =
      Operations.session_prompt_async(
        sid,
        %{parts: [%{type: "text", text: text}]},
        client
      )

    # Stream events, normalize them, and stop when the session goes idle
    event_stream
    |> Stream.map(&normalize_event/1)
    |> Stream.reject(&is_nil/1)
    |> Stream.transform(:running, fn
      _event, :done ->
        {:halt, :done}

      :turn_complete, _acc ->
        {[:turn_complete], :done}

      event, :running ->
        {[event], :running}
    end)
  end

  def stop(%{server: server}) do
    OpenCode.close(%{server: server})
  end

  # --- Event normalization ---

  # Text delta events (streaming text chunks)
  defp normalize_event(%OpenCode.Generated.EventMessagePartDelta{
         properties: %{delta: delta, field: "text"}
       })
       when is_binary(delta) do
    {:text_delta, delta}
  end

  # Full part updated — text
  defp normalize_event(%OpenCode.Generated.EventMessagePartUpdated{
         properties: %{part: %OpenCode.Generated.TextPart{text: text}}
       }) do
    {:text, text}
  end

  # Full part updated — tool (pending/running)
  defp normalize_event(%OpenCode.Generated.EventMessagePartUpdated{
         properties: %{
           part: %OpenCode.Generated.ToolPart{
             tool: name,
             state: %{status: status, input: input}
           }
         }
       })
       when status in ["pending", "running"] do
    {:tool_use_start, name, input}
  end

  # Full part updated — tool (completed)
  defp normalize_event(%OpenCode.Generated.EventMessagePartUpdated{
         properties: %{
           part: %OpenCode.Generated.ToolPart{
             tool: name,
             state: %OpenCode.Generated.ToolStateCompleted{output: output}
           }
         }
       }) do
    {:tool_result, name, truncate(inspect(output))}
  end

  # Full part updated — tool (error)
  defp normalize_event(%OpenCode.Generated.EventMessagePartUpdated{
         properties: %{
           part: %OpenCode.Generated.ToolPart{
             tool: name,
             state: %OpenCode.Generated.ToolStateError{error: error}
           }
         }
       }) do
    {:tool_result, name, "Error: #{inspect(error)}"}
  end

  # Session went idle — turn is complete
  defp normalize_event(%OpenCode.Generated.EventSessionIdle{}) do
    :turn_complete
  end

  # Session error
  defp normalize_event(%OpenCode.Generated.EventSessionError{properties: %{error: error}}) do
    {:error, inspect(error)}
  end

  # Ignore all other events (session.created, session.updated, etc.)
  defp normalize_event(_event), do: nil

  defp truncate(content) when is_binary(content) and byte_size(content) > 10_000 do
    String.slice(content, 0, 10_000) <> "\n... (truncated)"
  end

  defp truncate(content) when is_binary(content), do: content
  defp truncate(content), do: inspect(content)
end
