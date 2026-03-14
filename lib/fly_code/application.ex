defmodule FlyCode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if flame_runner?() do
      IO.puts("[FlyCode] FLAME runner starting (FLAME_PARENT=#{System.get_env("FLAME_PARENT")})")
    end

    children =
      if flame_runner?() do
        IO.puts("[FlyCode] Starting FLAME runner supervision tree (Telemetry + PubSub)")

        [
          FlyCodeWeb.Telemetry,
          {Phoenix.PubSub, name: FlyCode.PubSub},
          %{id: FlyCode.PG, start: {:pg, :start_link, [FlyCode.PG]}}
        ]
      else
        [
          FlyCodeWeb.Telemetry,
          FlyCode.Repo,
          FlyCode.Vault,
          {DNSCluster, query: Application.get_env(:fly_code, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: FlyCode.PubSub},
          %{id: FlyCode.PG, start: {:pg, :start_link, [FlyCode.PG]}},
          {FLAME.Pool,
           name: FlyCode.AgentPool,
           min: 0,
           max: 15,
           max_concurrency: 1,
           idle_shutdown_after: :timer.minutes(10),
           timeout: :timer.minutes(15),
           boot_timeout: :timer.minutes(5),
           backend: Application.get_env(:fly_code, :flame_backend, FLAME.LocalBackend)},
          FlyCode.Agent.Coordinator,
          FlyCodeWeb.Endpoint
        ]
      end

    opts = [strategy: :one_for_one, name: FlyCode.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp flame_runner?, do: System.get_env("FLAME_PARENT") != nil

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FlyCodeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
