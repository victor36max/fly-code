defmodule FlyCode.Agent.Hooks do
  @moduledoc """
  ClaudeCode lifecycle hooks.
  Broadcasts tool events to PubSub and enforces permissions.
  """

  require Logger

  def pre_tool_use(pubsub_topic, tool_name, input) do
    Phoenix.PubSub.broadcast(
      FlyCode.PubSub,
      pubsub_topic,
      {:agent_event, {:tool_start, tool_name, input}}
    )

    FlyCode.Agent.Permissions.check(tool_name, input)
  end

  def post_tool_use(pubsub_topic, tool_name, _input, output) do
    truncated =
      if is_binary(output) and byte_size(output) > 10_000 do
        String.slice(output, 0, 10_000) <> "\n... (truncated)"
      else
        output
      end

    Phoenix.PubSub.broadcast(
      FlyCode.PubSub,
      pubsub_topic,
      {:agent_event, {:tool_result, tool_name, truncated}}
    )
  end
end
