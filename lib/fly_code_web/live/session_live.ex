defmodule FlyCodeWeb.SessionLive do
  use FlyCodeWeb, :live_view

  alias FlyCode.Agent.Coordinator
  alias FlyCode.Sessions

  @impl true
  def mount(%{"id" => session_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FlyCode.PubSub, "session:#{session_id}")
      send(self(), :refresh_status)
    end

    db_session = Sessions.get_session_by_session_id(session_id)

    {messages, setup_output} =
      if connected?(socket) do
        msgs =
          case Coordinator.get_messages(session_id) do
            {:ok, msgs} -> msgs
            {:error, _} -> []
          end

        setup =
          case Coordinator.get_setup_state(session_id) do
            {:ok, lines} -> lines
            {:error, _} -> []
          end

        {msgs, setup}
      else
        {[], []}
      end

    backend = (db_session && db_session.backend) || :claude_code

    {:ok,
     assign(socket,
       page_title: "Session #{String.slice(session_id, 0..7)}",
       session_id: session_id,
       db_session: db_session,
       status: (db_session && db_session.status) || :unknown,
       backend: backend,
       messages: messages,
       current_text: "",
       streaming: false,
       input_text: "",
       setup_output: setup_output,
       current_model: default_model(backend),
       current_mode: "build",
       available_models: available_models(backend)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.react
      name="SessionChat"
      session_id={@session_id}
      db_session={serialize_db_session(@db_session)}
      status={Atom.to_string(@status)}
      backend={Atom.to_string(@backend)}
      messages={serialize_messages(@messages)}
      current_text={@current_text}
      streaming={@streaming}
      input_text={@input_text}
      setup_output={@setup_output}
      current_model={@current_model}
      current_mode={@current_mode}
      available_models={@available_models}
    />
    """
  end

  defp serialize_db_session(nil), do: nil

  defp serialize_db_session(session) do
    %{
      project: if(session.project, do: %{name: session.project.name}, else: nil)
    }
  end

  defp serialize_messages(messages) do
    Enum.map(messages, fn msg ->
      base = %{id: msg.id, role: Atom.to_string(msg.role), content: msg.content}

      base =
        if Map.has_key?(msg, :tool_name), do: Map.put(base, :tool_name, msg.tool_name), else: base

      if Map.has_key?(msg, :tool_input),
        do: Map.put(base, :tool_input, msg.tool_input),
        else: base
    end)
  end

  @impl true
  def handle_event("send_message", %{"text" => text}, socket) when text != "" do
    user_msg = %{id: System.unique_integer([:positive]), role: :user, content: text}

    case Coordinator.send_message(socket.assigns.session_id, text) do
      :ok ->
        {:noreply,
         socket
         |> update(:messages, &(&1 ++ [user_msg]))
         |> assign(streaming: true, current_text: "", input_text: "")}

      {:error, :session_not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found or has been shut down")}
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"text" => text}, socket) do
    {:noreply, assign(socket, input_text: text)}
  end

  def handle_event("set_model", %{"model" => model}, socket) do
    Coordinator.set_model(socket.assigns.session_id, model)
    {:noreply, socket}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    Coordinator.set_mode(socket.assigns.session_id, mode_atom)
    {:noreply, socket}
  end

  def handle_event("interrupt", _params, socket) do
    Coordinator.interrupt(socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_status, socket) do
    case Sessions.get_session_by_session_id(socket.assigns.session_id) do
      %{status: status} -> {:noreply, assign(socket, status: status)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:status, _session_id, status}, socket) do
    {:noreply, assign(socket, status: status)}
  end

  def handle_info({:setup_output, line}, socket) do
    {:noreply, update(socket, :setup_output, &(&1 ++ [line]))}
  end

  def handle_info({:model_changed, model}, socket) do
    {:noreply, assign(socket, current_model: model)}
  end

  def handle_info({:mode_changed, mode}, socket) do
    {:noreply, assign(socket, current_mode: Atom.to_string(mode))}
  end

  def handle_info({:agent_event, {:text, content}}, socket) do
    assistant_msg = %{id: System.unique_integer([:positive]), role: :assistant, content: content}

    {:noreply,
     socket
     |> update(:messages, &(&1 ++ [assistant_msg]))
     |> assign(streaming: false, current_text: "")}
  end

  def handle_info({:agent_event, {:text_delta, delta}}, socket) do
    {:noreply, assign(socket, current_text: socket.assigns.current_text <> delta)}
  end

  def handle_info({:agent_event, {:tool_use_start, name, input}}, socket) do
    tool_msg = %{
      id: System.unique_integer([:positive]),
      role: :tool,
      tool_name: name,
      tool_input: serialize_tool_input(input),
      content: "Running..."
    }

    {:noreply, update(socket, :messages, &(&1 ++ [tool_msg]))}
  end

  def handle_info({:agent_event, {:tool_start, name, input}}, socket) do
    tool_msg = %{
      id: System.unique_integer([:positive]),
      role: :tool,
      tool_name: name,
      tool_input: serialize_tool_input(input),
      content: "Running..."
    }

    {:noreply, update(socket, :messages, &(&1 ++ [tool_msg]))}
  end

  def handle_info({:agent_event, {:tool_result, _name, output}}, socket) do
    # Update the most recent tool message with its output
    messages =
      socket.assigns.messages
      |> Enum.reverse()
      |> update_last_tool(output)
      |> Enum.reverse()

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:agent_event, :turn_complete}, socket) do
    # Flush any remaining streaming text as a message
    socket =
      if socket.assigns.current_text != "" do
        msg = %{
          id: System.unique_integer([:positive]),
          role: :assistant,
          content: socket.assigns.current_text
        }

        socket
        |> update(:messages, &(&1 ++ [msg]))
        |> assign(current_text: "")
      else
        socket
      end

    {:noreply, assign(socket, streaming: false)}
  end

  def handle_info({:agent_event, {:error, message}}, socket) do
    error_msg = %{id: System.unique_integer([:positive]), role: :error, content: message}

    {:noreply,
     socket
     |> update(:messages, &(&1 ++ [error_msg]))
     |> assign(streaming: false)}
  end

  def handle_info({:agent_event, {:raw, _content}}, socket) do
    # Ignore raw events for now
    {:noreply, socket}
  end

  defp update_last_tool([%{role: :tool} = msg | rest], output) do
    [%{msg | content: output} | rest]
  end

  defp update_last_tool([head | rest], output) do
    [head | update_last_tool(rest, output)]
  end

  defp update_last_tool([], _output), do: []

  defp serialize_tool_input(input) when is_map(input) do
    case Jason.encode(input) do
      {:ok, json} -> json
      _ -> inspect(input)
    end
  end

  defp serialize_tool_input(input), do: inspect(input)

  defp default_model(:claude_code), do: "sonnet"
  defp default_model(:opencode), do: "default"
  defp default_model(_), do: "sonnet"

  defp available_models(:claude_code) do
    [
      %{id: "sonnet", name: "Sonnet"},
      %{id: "opus", name: "Opus"},
      %{id: "haiku", name: "Haiku"}
    ]
  end

  defp available_models(:opencode) do
    [%{id: "default", name: "Default"}]
  end

  defp available_models(_), do: [%{id: "sonnet", name: "Sonnet"}]
end
