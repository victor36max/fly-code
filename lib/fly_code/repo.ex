defmodule FlyCode.Repo do
  use Ecto.Repo,
    otp_app: :fly_code,
    adapter: Ecto.Adapters.Postgres
end
