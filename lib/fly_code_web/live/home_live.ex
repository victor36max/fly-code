defmodule FlyCodeWeb.HomeLive do
  use FlyCodeWeb, :live_view

  alias FlyCode.Projects
  alias FlyCode.Agent.Coordinator

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list_projects()
    active_sessions = Coordinator.list_active_sessions()

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       projects: projects,
       active_sessions: active_sessions
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.react
        name="HomeDashboard"
        projects={serialize_projects(@projects)}
        active_sessions={serialize_active_sessions(@active_sessions)}
      />
    </Layouts.app>
    """
  end

  defp serialize_active_sessions(sessions) do
    Map.new(sessions, fn {session_id, %{project_id: project_id}} ->
      {session_id, %{project_id: project_id}}
    end)
  end

  defp serialize_projects(projects) do
    Enum.map(projects, fn p ->
      %{
        id: p.id,
        name: p.name,
        repo_url: p.repo_url,
        default_branch: p.default_branch
      }
    end)
  end
end
