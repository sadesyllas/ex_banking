defmodule ExBanking.UserHandler.Watcher do
  @moduledoc """
  This module is the charged with watching ExBanking.UserHandler pids
  and cleaning up after these pids die.

  It is not meant to be used directly from client code.

  For more information, please read the `ExBanking.UserHandler`
  `ExBanking.UserHandler.Watcher` section in file `README.md`.
  """

  @module __MODULE__

  use GenServer

  def start_link(_) do
    GenServer.start_link(@module, nil, name: @module)
  end

  def init(_) do
    {:ok, nil}
  end

  @spec watch(pid :: pid) :: :ok
  def watch(pid) do
    GenServer.call(@module, {:watch, pid})
  end

  def handle_call({:watch, pid}, _from, state) do    
    Process.monitor(pid)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    with [{pid, user}] <- :ets.lookup(:user_handlers, pid) do
      :ets.delete(:user_handlers, user)
      :ets.delete(:user_handlers, pid)
    end

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
