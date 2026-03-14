defmodule FlyCodeWeb.ProjectLive.Show do
  use FlyCodeWeb, :live_view

  alias FlyCode.Projects
  alias FlyCode.Sessions
  alias FlyCode.Agent.Coordinator

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project!(id)
    sessions = Sessions.list_sessions_for_project(project.id)
    env_var_count = length(Projects.list_env_vars(project.id))
    env_keys = Projects.env_var_keys(project.id)

    {:ok,
     assign(socket,
       page_title: project.name,
       project: project,
       sessions: sessions,
       env_var_count: env_var_count,
       env_keys: env_keys,
       missing_tokens: compute_missing_tokens(env_keys, :claude_code),
       starting_session: false,
       backend: :claude_code
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.react
        name="ProjectShow"
        project={serialize_project(@project)}
        sessions={serialize_sessions(@sessions)}
        env_var_count={@env_var_count}
        missing_tokens={@missing_tokens}
        starting_session={@starting_session}
        backend={Atom.to_string(@backend)}
      />
    </Layouts.app>
    """
  end

  defp serialize_project(project) do
    %{
      id: project.id,
      name: project.name,
      repo_url: project.repo_url,
      default_branch: project.default_branch,
      setup_script: project.setup_script
    }
  end

  defp serialize_sessions(sessions) do
    Enum.map(sessions, fn s ->
      %{
        id: s.id,
        session_id: s.session_id,
        status: Atom.to_string(s.status),
        backend: Atom.to_string(s.backend),
        branch: s.branch,
        inserted_at: Calendar.strftime(s.inserted_at, "%Y-%m-%d %H:%M")
      }
    end)
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    if socket.assigns.starting_session do
      {:noreply, socket}
    else
      send(self(), :do_start_session)
      {:noreply, assign(socket, starting_session: true)}
    end
  end

  def handle_event("save_setup_script", %{"setup_script" => script}, socket) do
    # Store empty string as nil
    script = if script == "", do: nil, else: script

    case Projects.update_project(socket.assigns.project, %{setup_script: script}) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(project: project)
         |> put_flash(:info, "Setup script saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save setup script")}
    end
  end

  def handle_event("set_backend", %{"backend" => backend}, socket) do
    backend = String.to_existing_atom(backend)
    missing = compute_missing_tokens(socket.assigns.env_keys, backend)
    {:noreply, assign(socket, backend: backend, missing_tokens: missing)}
  end

  @impl true
  def handle_info(:do_start_session, socket) do
    case Coordinator.start_session(socket.assigns.project.id, backend: socket.assigns.backend) do
      {:ok, %{session_id: session_id}} ->
        {:noreply, push_navigate(socket, to: ~p"/session/#{session_id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(starting_session: false)
         |> put_flash(:error, "Failed to start session: #{inspect(reason)}")}
    end
  end

  defp compute_missing_tokens(env_keys, backend) do
    missing = if MapSet.member?(env_keys, "GIT_TOKEN"), do: [], else: ["GIT_TOKEN"]

    missing ++
      case backend do
        :claude_code ->
          has_key =
            MapSet.member?(env_keys, "ANTHROPIC_API_KEY") or
              MapSet.member?(env_keys, "CLAUDE_CODE_OAUTH_TOKEN")

          if has_key, do: [], else: ["ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN"]

        :opencode ->
          []
      end
  end
end
