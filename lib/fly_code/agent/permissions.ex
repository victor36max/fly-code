defmodule FlyCode.Agent.Permissions do
  @moduledoc """
  Tool permission policy for agent sessions.
  Blocks dangerous terminal commands while allowing normal dev workflow.
  """

  @blocked_patterns [
    ~r/rm\s+-rf\s+\/(?!tmp)/,
    ~r/\bsudo\b/,
    ~r/curl.*\|\s*(?:sh|bash)/,
    ~r/mkfs\b/,
    ~r/dd\s+if=/
  ]

  def check("terminal", %{"command" => cmd}) do
    if Enum.any?(@blocked_patterns, &Regex.match?(&1, cmd)) do
      {:deny, "Command blocked by security policy"}
    else
      :allow
    end
  end

  def check(_tool_name, _input), do: :allow
end
