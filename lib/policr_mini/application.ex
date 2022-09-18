defmodule PolicrMini.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    PolicrMini.Mnesia.init()
    PolicrMini.Worker.GeneralRun.init_queue()

    children = [
      # Start the Ecto repository
      PolicrMini.Repo,
      # 缓存
      PolicrMini.Cache,
      # 线上操作数据库服务
      PolicrMini.DBServer,
      # 计数器
      PolicrMini.Counter,
      # 获取并维护全局默认值。
      PolicrMini.DefaultsServer,
      # Start the Telemetry supervisor
      PolicrMiniWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: PolicrMini.PubSub},
      # Start the Endpoint (http/https)
      PolicrMiniWeb.Endpoint
    ]

    children =
      if PolicrMini.mix_env() == :test,
        do: children,
        else: children ++ [PolicrMiniBot.Supervisor]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PolicrMini.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    PolicrMiniWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
