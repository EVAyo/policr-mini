defmodule PolicrMiniBot.Supervisor do
  @moduledoc false

  use Supervisor

  alias PolicrMiniBot.{
    InitTakeoveredPlug,
    InitFromPlug,
    InitUserJoinedActionPlug,
    HandleUserJoinedGroupPlug,
    HandleSelfJoinedPlug,
    HandleSelfLeftedPlug,
    HandleAdminPermissionsChangePlug,
    HandleSelfPermissionsChangePlug,
    RespStartCmdPlug,
    RespPingCmdPlug,
    RespSyncCmdPlug,
    RespLoginCmdPlug,
    RespSponsorshipCmdPlug,
    HandleUserJoinedCleanupPlug,
    HandleMemberRemovedPlug,
    HandleNewChatTitlePlug,
    HandleNewChatPhotoPlug,
    HandlePrivateAttachmentPlug,
    CallVerificationPlug,
    CallRevokeTokenPlug,
    CallEnablePlug,
    CallLeavePlug
  }

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # 初始化消息清理任务
    PolicrMiniBot.Worker.MessageCleaner.init_queue()
    PolicrMiniBot.Worker.ValidationTerminator.init_queue()

    install_plugs([
      InitTakeoveredPlug,
      InitFromPlug,
      InitUserJoinedActionPlug,
      RespStartCmdPlug,
      RespPingCmdPlug,
      RespSyncCmdPlug,
      RespLoginCmdPlug,
      RespSponsorshipCmdPlug,
      # ↓此模块↓ 需保证安装在 `InitUserJoinedActionPlug` 模块的后面。
      HandleUserJoinedGroupPlug,
      PolicrMiniBot.HandleUserLeftGroupPlug,
      PolicrMiniBot.HandleGroupMemberLeftMessagePlug,
      HandleSelfJoinedPlug,
      HandleSelfLeftedPlug,
      # ↓此模块↓ 需保证安装在 `HandleUserLeftGroupPlug` 模块的后面。
      HandleAdminPermissionsChangePlug,
      # ↓此模块↓ 需保证安装在 `InitUserJoinedActionPlug` 和 `HandleSelfLeftedPlug` 模块的后面。
      HandleSelfPermissionsChangePlug,
      HandleUserJoinedCleanupPlug,
      HandleNewChatTitlePlug,
      HandleNewChatPhotoPlug,
      HandleMemberRemovedPlug,
      HandlePrivateAttachmentPlug,
      CallVerificationPlug,
      CallRevokeTokenPlug,
      CallEnablePlug,
      CallLeavePlug
    ])

    # !注意! 因为以上的验证排除条件，此模块需要保证在填充以上条件的模块的处理流程的后面。
    children = [
      # 任务缓存
      PolicrMiniBot.Worker.JobCacher,
      # 图片提供服务
      PolicrMiniBot.ImageProvider,
      # 消息清理服务
      PolicrMiniBot.Cleaner,
      # 一次性处理保证
      PolicrMiniBot.Disposable,
      # 速度限制。
      PolicrMiniBot.SpeedLimiter,
      # 任务调度服务
      PolicrMiniBot.Scheduler,
      # 拉取更新消息
      PolicrMiniBot.UpdatesPoller,
      # 消费消息的动态主管
      PolicrMiniBot.Consumer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end

  defp install_plugs(plugs) do
    Telegex.Plug.Pipeline.install_all(plugs)
  end
end
