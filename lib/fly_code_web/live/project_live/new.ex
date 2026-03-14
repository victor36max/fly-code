defmodule FlyCodeWeb.ProjectLive.New do
  use FlyCodeWeb, :live_view

  alias FlyCode.Projects
  alias FlyCode.Projects.Project

  @impl true
  def mount(_params, _session, socket) do
    changeset = Projects.change_project(%Project{})

    {:ok,
     assign(socket,
       page_title: "New Project",
       form: to_form(changeset)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.react name="ProjectNew" form={form_data(@form)} />
    </Layouts.app>
    """
  end

  defp form_data(form) do
    %{
      name: Phoenix.HTML.Form.input_value(form, :name) || "",
      repo_url: Phoenix.HTML.Form.input_value(form, :repo_url) || "",
      default_branch: Phoenix.HTML.Form.input_value(form, :default_branch) || "main",
      setup_script: Phoenix.HTML.Form.input_value(form, :setup_script) || "",
      errors: form_errors(form)
    }
  end

  defp form_errors(form) do
    Enum.reduce([:name, :repo_url, :default_branch, :setup_script], %{}, fn field, acc ->
      case form[field] do
        %{errors: errors} when errors != [] ->
          Map.put(acc, Atom.to_string(field), Enum.map(errors, fn {msg, _} -> msg end))

        _ ->
          acc
      end
    end)
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    case Projects.create_project(params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created!")
         |> push_navigate(to: ~p"/projects/#{project.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
