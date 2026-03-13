defmodule FlyCodeWeb.GlobalEnvLive do
  @moduledoc """
  Reuses EnvVarLive but scoped to global env vars.
  """
  use FlyCodeWeb, :live_view

  alias FlyCode.Projects
  alias FlyCode.Projects.EnvVar

  @impl true
  def mount(_params, _session, socket) do
    env_vars = Projects.list_env_vars(:global)

    {:ok,
     assign(socket,
       page_title: "Global Environment Variables",
       project: nil,
       env_vars: env_vars,
       scope: :global,
       new_key: "",
       new_value: "",
       revealed: MapSet.new()
     )
     |> allow_upload(:dotenv, accept: :any, max_entries: 1, max_file_size: 100_000)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.react
        name="GlobalEnvManager"
        env_vars={serialize_env_vars(@env_vars)}
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
    case Projects.create_env_var(%{key: key, value: value, scope: :global, project_id: nil}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(env_vars: Projects.list_env_vars(:global), new_key: "", new_value: "")
         |> put_flash(:info, "Global variable added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add variable")}
    end
  end

  def handle_event("delete_var", %{"id" => id}, socket) do
    env_var = FlyCode.Repo.get!(EnvVar, id)
    {:ok, _} = Projects.delete_env_var(env_var)

    {:noreply,
     socket
     |> assign(env_vars: Projects.list_env_vars(:global))
     |> put_flash(:info, "Variable deleted")}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("import_dotenv", _params, socket) do
    [content] =
      consume_uploaded_entries(socket, :dotenv, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    parsed = Projects.parse_dotenv(content)

    Enum.each(parsed, fn %{key: key, value: value} ->
      Projects.create_env_var(%{key: key, value: value, scope: :global, project_id: nil})
    end)

    {:noreply,
     socket
     |> assign(env_vars: Projects.list_env_vars(:global))
     |> put_flash(:info, "Imported #{length(parsed)} variables")}
  end
end
