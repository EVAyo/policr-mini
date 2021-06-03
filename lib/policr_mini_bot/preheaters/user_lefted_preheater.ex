defmodule PolicrMiniBot.UserLeftedPreheater do
  @moduledoc """
  群成员离开的处理器。
  """

  # TODO: 弃用此模块。由于 TG 上游的变动，加群已放弃对 `message` 的处理。因此 `telegex_plug` 库的预制的抽象模块已无法适应此需求，需改进库设计。

  # !注意! 此模块功能依赖对 `chat_member` 更新的接收。

  use PolicrMiniBot, plug: :preheater

  alias PolicrMini.PermissionBusiness

  @doc """
  根据更新消息中的 `chat_member` 字段，清理离开数据。

  ## 以下情况将不进入验证流程（按顺序匹配）：
  - 成员现在的状态如果是 `restricted`，但 `is_member` 为 `true`。
  - 成员现在的状态不是 `left`、`kicked` 二者之一。
  - 成员之前的状态是 `left`、`kicked` 二者之一。
  - 成员之前的状态如果是 `restricted`，但 `is_member` 为 `false`。
  - 离开的群成员是机器人自己。
  """
  @impl true
  def call(%{chat_member: nil} = _update, state) do
    {:ignored, state}
  end

  @impl true
  def call(%{chat_member: %{new_chat_member: %{is_member: is_member, status: status}}}, state)
      when status == "restricted" and is_member == true do
    {:ignored, state}
  end

  @impl true
  def call(%{chat_member: %{new_chat_member: %{status: status}}}, state)
      when status not in ["left", "kicked"] do
    {:ignored, state}
  end

  @impl true
  def call(%{chat_member: %{old_chat_member: %{status: status}}}, state)
      when status in ["left", "kicked"] do
    {:ignored, state}
  end

  @impl true
  def call(%{chat_member: %{old_chat_member: %{is_member: is_member, status: status}}}, state)
      when status == "restricted" and is_member == false do
    {:ignored, state}
  end

  @impl true
  def call(%{chat_member: chat_member} = _update, state) do
    %{chat: %{id: chat_id}, new_chat_member: %{user: %{id: lefted_user_id}}} = chat_member

    if lefted_user_id == bot_id() do
      # 跳过机器人自身

      {:ignored, state}
    else
      # 如果是管理员（非群主）则删除权限记录
      if perm = PermissionBusiness.find(chat_id, lefted_user_id) do
        unless perm.tg_is_owner do
          PermissionBusiness.delete(chat_id, lefted_user_id)
        end
      end
    end

    {:ok, %{state | done: true}}
  end
end
