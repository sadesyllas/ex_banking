defmodule ExBanking.Application do
  @moduledoc """
  Please, refer to the documentation of ExBanking.UserHandler for an explanation
  of the ETS tables that are set up in this module.
  """

  use Application

  def start(_type, _args) do
    ets_opts = [:set, :public, :named_table, {:write_concurrency, true}, {:read_concurrency, true}]

    :ets.new(:backlog, ets_opts)
    :ets.new(:user_balances, ets_opts)
    :ets.new(:user_handlers, ets_opts)

    Supervisor.start_link([
      ExBanking.UserHandler.Watcher
    ], [strategy: :one_for_one])
  end
end
