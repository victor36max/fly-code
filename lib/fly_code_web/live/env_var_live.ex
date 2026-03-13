defmodule FlyCodeWeb.EnvVarLive do
  use FlyCodeWeb, :live_view

  alias FlyCode.Projects
  alias FlyCode.Projects.EnvVar

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    project = Projects.get_project!(project_id)
    env_vars = Projects.list_env_vars(project.id)

    {:ok,
     assign(socket,
       page_title: "Env Vars - #{project.name}",
       project: project,
       env_vars: env_vars,
       scope: :project,
       new_key: "",
       new_value: "",
       revealed: MapSet.new(),
       upload_preview: nil
     )
     |> allow_upload(:dotenv, accept: :any, max_entries: 1, max_file_size: 100_000)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.react
        name="EnvVarManager"
        project={serialize_project(@project)}
        env_vars={serialize_env_vars(@env_vars)}
        scope={Atom.to_string(@scope)}
        revealed={MapSet.to_list(@revealed)}
        new_key={@new_key}
        new_value={@new_value}
      />

      <%!-- File upload stays in HEEx (requires live_file_input) --%>
      <div class="mt-6 rounded-xl border bg-card text-card-foreground shadow p-6">
        <h3 class="font-semibold mb-3">Import .env File</h3>
        <form phx-submit="import_dotenv" phx-change="validate_upload">
          <div class="flex gap-3 items-end">
            <div class="flex-1">
              <.live_file_input
                upload={@uploads.dotenv}
                class="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm"
              />
            </div>
            <button
              type="submit"
              class="inline-flex items-center justify-center rounded-md text-sm font-medium border border-input bg-background shadow-sm hover:bg-accent hover:text-accent-foreground h-9 px-4 py-2"
              disabled={@uploads.dotenv.entries == []}
            >
              Import
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end

  defp serialize_project(nil), do: nil
  defp serialize_project(project), do: %{id: project.id, name: project.name}

  defp serialize_env_vars(env_vars) do
    Enum.map(env_vars, fn ev ->
      %{id: ev.id, key: ev.key, value: ev.value, scope: Atom.to_string(ev.scope)}
    end)
  end

  @impl true
  def handle_event("toggle_reveal", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    revealed =
      if MapSet.member?(socket.assigns.revealed, id) do
        MapSet.delete(socket.assigns.revealed, id)
      else
        MapSet.put(socket.assigns.revealed, id)
      end

    {:noreply, assign(socket, revealed: revealed)}
  end

  def handle_event("add_var", %{"key" => key, "value" => value}, socket) do
    attrs = %{
      key: key,
      value: value,
      scope: socket.assigns.scope,
      project_id: if(socket.assigns.scope == :project, do: socket.assigns.project.id)
    }

    case Projects.create_env_var(attrs) do
      {:ok, _} ->
        env_vars = reload_env_vars(socket)

        {:noreply,
         socket
         |> assign(env_vars: env_vars, new_key: "", new_value: "")
         |> put_flash(:info, "Variable added")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add variable")}
    end
  end

  def handle_event("delete_var", %{"id" => id}, socket) do
    env_var = FlyCode.Repo.get!(EnvVar, id)
    {:ok, _} = Projects.delete_env_var(env_var)
    env_vars = reload_env_vars(socket)
    {:noreply, assign(socket, env_vars: env_vars) |> put_flash(:info, "Variable deleted")}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("import_dotenv", _params, socket) do
    [content] =
      consume_uploaded_entries(socket, :dotenv, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    parsed = Projects.parse_dotenv(content)

    Enum.each(parsed, fn %{key: key, value: value} ->
      Projects.create_env_var(%{
        key: key,
        value: value,
        scope: socket.assigns.scope,
        project_id: if(socket.assigns.scope == :project, do: socket.assigns.project.id)
      })
    end)

    env_vars = reload_env_vars(socket)

    {:noreply,
     socket
     |> assign(env_vars: env_vars, upload_preview: nil)
     |> put_flash(:info, "Imported #{length(parsed)} variables")}
  end

  defp reload_env_vars(socket) do
    case socket.assigns.scope do
      :global -> Projects.list_env_vars(:global)
      :project -> Projects.list_env_vars(socket.assigns.project.id)
    end
  end
end
