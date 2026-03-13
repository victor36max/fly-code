defmodule FlyCodeWeb.PageController do
  use FlyCodeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
