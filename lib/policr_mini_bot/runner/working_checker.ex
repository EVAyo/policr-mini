defmodule PolicrMiniBot.Runner.WorkingChecker do
  @moduledoc """
  工作状态检查任务。

  此模块会定期检查被接管群组中的机器人权限、以及是否已离开等状态。在不满足最低权限要求时给予提示并自动取消接管，或对已离开的群组直接取消接管。
  当发现普通群（非超级群）将直接取消接管，并删除所有权限记录。当发现频道时将直接取消接管。
  """

  alias PolicrMini.{Instances, ChatBusiness, PermissionBusiness}
  alias PolicrMini.Instances.Chat

  import PolicrMiniBot.Helper

  require Logger

  @doc """
  根据权限自动修正工作状态或执行退出。
  """
  @spec run :: :ok
  def run do
    Logger.info("Working status check started")

    takeovred_chats = ChatBusiness.find_takeovered()

    takeovred_chats
    |> Stream.each(&check_chat/1)
    |> Stream.run()

    Logger.info("Working status check finished")

    :ok
  end

  # 非超级群，提示并退出。
  defp check_chat(%{id: chat_id, is_take_over: true, type: "group"}) do
    send_message(chat_id, t("errors.non_super_group"))

    Telegex.leave_chat(chat_id)
  end

  # 频道，直接退出。
  defp check_chat(%{id: chat_id, is_take_over: true, type: "channel"}) do
    Telegex.leave_chat(chat_id)
  end

  # 检查必要的权限，并在不满足时进行相对应的处理。
  defp check_chat(%{is_take_over: true} = chat) do
    case Telegex.get_chat_member(chat.id, PolicrMiniBot.id()) do
      {:ok, member} ->
        # 检查权限并执行相应修正

        cond do
          member.can_send_messages == false ->
            # 如果没有发消息权限，直接退出
            Telegex.leave_chat(chat.id)

            Logger.info(
              "Missing permission to send message, automatically left the chat: #{inspect(chat_id: chat.id)}"
            )

          member.status != "administrator" ->
            # 如果不是管理员，取消接管
            cancel_takeover(chat, reason: :non_admin, send_notification: "errors.no_permission")

          member.can_restrict_members == false ->
            # 如果没有限制用户的权限，取消接管
            cancel_takeover(chat,
              reason: :missing_permissions,
              send_notification: "errors.no_permission"
            )

          member.can_delete_messages == false ->
            # 如果没有删除消息的权限，取消接管
            cancel_takeover(chat,
              reason: :missing_permissions,
              send_notification: "errors.no_permission"
            )

          true ->
            # 具备权限，忽略处理
            :ok
        end

      {:error, %Telegex.Model.RequestError{reason: :timeout}} ->
        # 处理超时，自动重试
        Logger.warning(
          "Checking own permission timeout, waiting for retry: #{inspect(chat_id: chat.id)}"
        )

        :timer.sleep(150)

        check_chat(chat)

      {:error, error} ->
        # 检查时发生其它错误，进一步处理错误
        handle_check_error(error, chat)
    end
  end

  @err_desc_bot_was_kicked "Forbidden: bot was kicked from the supergroup chat"
  @err_desc_bot_is_not_member [
    # 超级群
    "Forbidden: bot is not a member of the supergroup chat",
    # 普通群
    "Forbidden: bot is not a member of the group chat"
  ]
  @err_desc_chat_not_found "Bad Request: chat not found"
  @err_desc_was_upgraded_supergroup "Bad Request: group chat was upgraded to a supergroup chat"

  # 机器人被封禁，取消接管。
  defp handle_check_error(%Telegex.Model.Error{description: description}, chat)
       when description == @err_desc_bot_was_kicked,
       do: cancel_takeover(chat, reason: :kicked)

  # 机器人已不在群中，取消接管。
  defp handle_check_error(%Telegex.Model.Error{description: description}, chat)
       when description in @err_desc_bot_is_not_member,
       do: cancel_takeover(chat, reason: :left)

  # 已被升级为超级群，取消接管。
  # 一些未经证实的猜测：
  # 此错误提示表示旧群 ID 仍然被 TG 识别，但是 ID 的作用已被废弃。理论上这类群组需要清理，否则会出现资料重复的群组。
  defp handle_check_error(%Telegex.Model.Error{description: description}, chat)
       when description == @err_desc_was_upgraded_supergroup,
       do: cancel_takeover(chat, reason: :upgraded)

  # 群组已不存在。取消接管，并删除与之相关的用户权限。
  defp handle_check_error(%Telegex.Model.Error{description: description}, chat)
       when description == @err_desc_chat_not_found do
    cancel_takeover(chat, reason: :not_found)

    PermissionBusiness.delete_all(chat.id)
  end

  # 未知错误
  defp handle_check_error(error, chat)
       when is_struct(error, Telegex.Model.Error) or is_struct(error, Telegex.Model.RequestError) do
    Logger.error("Self-permissions check failed", chat_id: chat.id, error: error)
  end

  @type cancel_reason ::
          :non_admin
          | :missing_permissions
          | :kicked
          | :left
          | :upgraded
          | :not_found

  @type text_key :: String.t()
  @type cancel_takeover_opts :: [reason: cancel_reason, send_notification: text_key]

  # 取消接管
  @spec cancel_takeover(Chat.t(), cancel_takeover_opts) :: :ok
  defp cancel_takeover(%{id: chat_id} = chat, opts) do
    Instances.cancel_chat_takeover(chat)

    if text_key = Keyword.get(opts, :send_notification) do
      async do
        send_message(
          chat.id,
          t(text_key, %{bot_username: PolicrMiniBot.username()}),
          parse_mode: nil
        )
      end
    end

    reason = Keyword.get(opts, :reason, :none)

    Logger.info(
      "The takeover has been automatically cancelled: #{inspect(chat_id: chat_id, reason: reason)}"
    )

    :ok
  end
end
