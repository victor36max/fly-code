defmodule FlyCode.Agent.HooksTest do
  use ExUnit.Case, async: true

  alias FlyCode.Agent.Hooks

  setup do
    topic = "test:hooks:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(FlyCode.PubSub, topic)
    {:ok, topic: topic}
  end

  describe "pre_tool_use/3" do
    test "broadcasts tool_start event", %{topic: topic} do
      result = Hooks.pre_tool_use(topic, "read_file", %{"path" => "/tmp/f"})

      assert_receive {:agent_event, {:tool_start, "read_file", %{"path" => "/tmp/f"}}}
      assert result == :allow
    end

    test "returns deny for blocked commands", %{topic: topic} do
      result = Hooks.pre_tool_use(topic, "terminal", %{"command" => "sudo rm -rf /"})

      assert_receive {:agent_event, {:tool_start, "terminal", _}}
      assert {:deny, _} = result
    end
  end

  describe "post_tool_use/4" do
    test "broadcasts tool_result event", %{topic: topic} do
      Hooks.post_tool_use(topic, "read_file", %{}, "file contents")

      assert_receive {:agent_event, {:tool_result, "read_file", "file contents"}}
    end

    test "truncates output longer than 10KB", %{topic: topic} do
      large_output = String.duplicate("x", 15_000)
      Hooks.post_tool_use(topic, "terminal", %{}, large_output)

      assert_receive {:agent_event, {:tool_result, "terminal", truncated}}
      assert byte_size(truncated) < 15_000
      assert String.ends_with?(truncated, "... (truncated)")
    end

    test "passes through non-binary output as-is", %{topic: topic} do
      Hooks.post_tool_use(topic, "tool", %{}, {:ok, 42})

      assert_receive {:agent_event, {:tool_result, "tool", {:ok, 42}}}
    end
  end
end
