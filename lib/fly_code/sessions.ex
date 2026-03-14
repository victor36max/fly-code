defmodule FlyCode.Sessions do
  import Ecto.Query
  alias FlyCode.Repo
  alias FlyCode.Sessions.Session

  def list_sessions do
    Repo.all(from s in Session, order_by: [desc: s.inserted_at], preload: :project)
  end

  def list_sessions_for_project(project_id) do
    Repo.all(
      from s in Session,
        where: s.project_id == ^project_id,
        order_by: [desc: s.inserted_at]
    )
  end

  def get_session!(id), do: Repo.get!(Session, id) |> Repo.preload(:project)

  def get_session_by_session_id(session_id) do
    Repo.get_by(Session, session_id: session_id) |> maybe_preload()
  end

  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  def update_session_status(session_id, status) do
    case Repo.get_by(Session, session_id: session_id) do
      nil -> {:error, :not_found}
      session -> session |> Ecto.Changeset.change(status: status) |> Repo.update()
    end
  end

  @in_progress_statuses [:spawning, :cloning, :setup_script, :spawning_agent, :active]

  def shutdown_stale_sessions do
    from(s in Session, where: s.status in ^@in_progress_statuses)
    |> Repo.update_all(set: [status: :shutdown])
  end

  def shutdown_unrecovered_sessions(recovered_session_ids) do
    recovered_list = MapSet.to_list(recovered_session_ids)

    query =
      if Enum.empty?(recovered_list) do
        from(s in Session, where: s.status in ^@in_progress_statuses)
      else
        from(s in Session,
          where: s.status in ^@in_progress_statuses,
          where: s.session_id not in ^recovered_list
        )
      end

    Repo.update_all(query, set: [status: :shutdown])
  end

  defp maybe_preload(nil), do: nil
  defp maybe_preload(session), do: Repo.preload(session, :project)
end
