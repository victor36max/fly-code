defmodule FlyCode.Agent.Backends.ClaudeCode do
  @moduledoc """
  Backend adapter for the ClaudeCode SDK.
  """

  alias ClaudeCode.Content.{ToolUseBlock, ToolResultBlock}
  alias ClaudeCode.Message.{AssistantMessage, PartialAssistantMessage, ResultMessage, UserMessage}

  def start(session_id, workspace_path, _pubsub_topic) do
    ClaudeCode.start_link(
      model: "sonnet",
      session_id: session_id,
      cwd: workspace_path,
      cli_path: System.find_executable("claude"),
      permission_mode: :bypass_permissions,
      allow_dangerously_skip_permissions: true,
      include_partial_messages: true
    )
  end

  def stream(client, text) do
    client
    |> ClaudeCode.stream(text)
    |> Stream.flat_map(&normalize/1)
  end

  def stop(_client), do: :ok

  # Streaming text deltas
  defp normalize(%PartialAssistantMessage{} = msg) do
    case PartialAssistantMessage.extract_text(msg) do
      {:ok, text} -> [{:text_delta, text}]
      :error -> []
    end
  end

  # Complete assistant message — extract text and tool uses from content blocks
  defp normalize(%AssistantMessage{message: %{content: content}}) do
    Enum.flat_map(content, fn
      %ToolUseBlock{name: name, input: input} ->
        [{:tool_use_start, name, input}]

      _block ->
        []
    end)
  end

  # User message — contains tool results
  defp normalize(%UserMessage{message: %{content: content}}) when is_list(content) do
    Enum.flat_map(content, fn
      %ToolResultBlock{content: result_content} ->
        [{:tool_result, "tool", truncate(extract_tool_result_text(result_content))}]

      _block ->
        []
    end)
  end

  # Final result
  defp normalize(%ResultMessage{is_error: true} = msg) do
    [{:error, to_string(msg)}]
  end

  defp normalize(%ResultMessage{}), do: []

  # Catch-all
  defp normalize(_event), do: []

  defp extract_tool_result_text(content) when is_binary(content), do: content

  defp extract_tool_result_text(content) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{text: text} -> text
      other -> inspect(other)
    end)
  end

  defp extract_tool_result_text(content), do: inspect(content)

  defp truncate(content) when is_binary(content) and byte_size(content) > 10_000 do
    String.slice(content, 0, 10_000) <> "\n... (truncated)"
  end

  defp truncate(content) when is_binary(content), do: content
  defp truncate(content), do: inspect(content)
end
