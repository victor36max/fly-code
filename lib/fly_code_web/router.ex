defmodule FlyCodeWeb.Router do
  use FlyCodeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FlyCodeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", FlyCodeWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/projects/new", ProjectLive.New
    live "/projects/:id", ProjectLive.Show
    live "/projects/:id/env", EnvVarLive
    live "/settings/env", GlobalEnvLive
    live "/session/:id", SessionLive
  end
end
