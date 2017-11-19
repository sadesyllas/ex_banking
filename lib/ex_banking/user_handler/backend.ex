defmodule ExBanking.UserHandler.Backend do
  @moduledoc """
  This module is the private API of ExBanking.UserHandler.

  It is not meant to be used directly from client code.

  For more information, please read the `ExBanking.UserHandler`
  section in file `README.md`.
  """

  @type banking_error :: ExBanking.banking_error

  require Logger

  alias ExBanking.UserHandler
  alias ExBanking.UserHandler.Watcher

  ######################
  # API IMPLEMENTATION #
  ######################

  @doc """
  Deposit to the user's balance.

  Here, the key for the :user_balances ETS table is {user, currency}.
  """
  @spec deposit(user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, new_balance :: number} | banking_error
  def deposit(user, amount, currency) do
    result =
      case :ets.lookup(:user_balances, {user, currency}) do
        [] ->
            :ets.insert(:user_balances, {{user, currency}, amount})
            {:ok, amount}
        [{_, balance}] ->
          deposit_result = balance + amount
          :ets.insert(:user_balances, {{user, currency}, deposit_result})
          {:ok, deposit_result}
      end
    Logger.debug("Depositing #{amount}#{currency} to #{user}: #{inspect(result)}")
    result
  end

  @doc """
  Withdraw from the user's balance.

  Here, the key for the :user_balances ETS table is {user, currency}.

  If the balance is less than the amount, the operation fails.
  """
  @spec withdraw(user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, new_balance :: number} | banking_error
  def withdraw(user, amount, currency) do
    result =
      case :ets.lookup(:user_balances, {user, currency}) do
        [] -> {:error, :not_enough_money}
        [{_, balance}] when balance < amount -> {:error, :not_enough_money}
        [{_, balance}] ->
          withdraw_result = balance - amount
          :ets.insert(:user_balances, {{user, currency}, withdraw_result})
          {:ok, withdraw_result}
      end
    Logger.debug("Withdrawing #{amount}#{currency} from #{user}: #{inspect(result)}")
    result
  end

  @spec get_balance(user :: String.t, currency :: String.t)
    :: {:ok, balance :: number} | banking_error
  def get_balance(user, currency) do
    balance =
      case :ets.lookup(:user_balances, {user, currency}) do
        [] -> 0.0
        [{_, balance}] -> balance
      end
    {:ok, balance}
  end

  @doc """
  Make sure that we have existent sender and receiver and that they can
  service the request.

  If all is ok, then proceed with the operation of a withdrawal followed by a deposit.

  If the deposit fails, the withdrawed amount is returned to the sender.
  """
  @spec send(from_user :: String.t, to_user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
  def send(sender, receiver, amount, currency) do
    result =
      with {:exists1, :ok} <- {:exists1, exists?(sender)},
          {:exists2, :ok} <- {:exists2, exists?(receiver)},
          sender_pid <- get_pid(sender),
          receiver_pid <- get_pid(receiver),
          {:backlog1, :ok} <- {:backlog1, try_add_backlog(sender)},
          {:backlog2, :ok} <- {:backlog2, try_add_backlog(receiver)} do
        result = do_send(sender, sender_pid, receiver, receiver_pid, amount, currency)    
        remove_backlog(sender)
        remove_backlog(receiver)
        result
      else
        {:exists1, {:error, :user_does_not_exist}} -> {:error, :sender_does_not_exist}
        {:exists2, {:error, :user_does_not_exist}} -> {:error, :receiver_does_not_exist}
        {:backlog1, {:error, :user_does_not_exist}} -> {:error, :sender_does_not_exist}
        {:backlog2, {:error, :user_does_not_exist}} -> {:error, :receiver_does_not_exist}
        {:backlog1, {:error, :too_many_requests_to_user}} -> {:error, :too_many_requests_to_sender}
        {:backlog2, {:error, :too_many_requests_to_user}} ->
          remove_backlog(sender)
          {:error, :too_many_requests_to_receiver}
      end
    Logger.debug("Sending #{amount}#{currency} from #{sender} to #{receiver}: #{inspect(result)}")
    result
  end

  ###########
  # HELPERS #
  ###########

  def schedule_stale_check() do
    # 30 seconds in milliseconds
    stale_check_interval = Application.get_env(:ex_banking, :config)[:stale_check_interval] || 30000
    Process.send_after(self(), :stale_check, stale_check_interval)
  end

  @doc """
  Create a new user handler process or return the already created one.
  """
  @spec get_pid(user :: binary) :: pid
  def get_pid(user)
  def get_pid(user), do: get_pid(:ets.lookup(:backlog, user), user)
  def get_pid([], _user), do: {:error, :user_does_not_exist}
  def get_pid(_, user) do
    {:ok, pid} = GenServer.start(UserHandler, nil)

    # insert both {user, pid} and {pid, user} to optimize
    # retrieval of the data by ExBanking.UserHandler.Watcher's
    # :EXIT handling logic.
    if :ets.insert_new(:user_handlers, {user, pid}) do
      :ets.insert(:user_handlers, {pid, user})
      Watcher.watch(pid)
      GenServer.cast(pid, :init)
      Logger.debug("Created new user handler process for #{user}")
      pid
    else
      Process.exit(pid, :normal)
      [{_, pid}] = :ets.lookup(:user_handlers, user)
      Logger.debug("User handler process for #{user} already exists")
      pid
    end
  end

  @spec try_add_backlog(user :: binary) :: :ok | banking_error
  def try_add_backlog(user) do
    try do
      if :ets.update_counter(:backlog, user, {2, 1}) > 10 do
        :ets.update_counter(:backlog, user, {2, -1})
        {:error, :too_many_requests_to_user}
      else
        :ok
      end
    rescue
      ArgumentError -> {:error, :user_does_not_exist}
    end
  end

  @spec remove_backlog(user :: binary) :: :ok | banking_error
  def remove_backlog(user) do
    try do
      :ets.update_counter(:backlog, user, {2, -1, -1, 0})
    rescue
      ArgumentError -> nil
    end
    :ok
  end

  @spec exists?(user :: binary) :: :ok | banking_error
  def exists?(user), do: exists?(:ets.lookup(:backlog, user), user)
  def exists?([], _user), do: {:error, :user_does_not_exist}
  def exists?(_, _user), do: :ok

  @doc """
  Make sure that the user exists and the we have a valid pid to call GenServer.call on it.

  If all is ok, we make the call to the GenServer to get the result.
  """
  @spec execute_operation(user :: binary, operation :: tuple)
    :: success :: term | banking_error
  def execute_operation(user, operation) do
    with :ok <- exists?(user),
         pid <- get_pid(user),
         :ok <- try_add_backlog(user) do
      result = execute_operation_do_call(user, pid, operation)
      remove_backlog(user)
      result
    end
  end

  @doc """
  Make the actual call as per the logic of execute_operation.
  """
  @spec execute_operation_do_call(user :: binary, pid :: pid, operation :: tuple)
    :: success :: term | banking_error
  defp execute_operation_do_call(user, pid, operation) do
    try do
      GenServer.call(pid, operation)
    catch :exit, {:noproc, _} ->
      user |> get_pid() |> GenServer.call(operation)
    end
  end

  @doc """
  Part of send which does the actual money tranfers.
  """
  @spec do_send(sender :: binary, sender_pid :: pid,
    receiver :: binary, receiver_pid :: pid,
    amount :: float, currency :: binary)
      :: {:ok, new_sender_balance :: float, new_receiver_balance :: float} | banking_error
  defp do_send(sender, sender_pid, receiver, receiver_pid, amount, currency) do
    with\
      {:withdrawal, {:ok, sender_balance}} <-
        {:withdrawal, execute_operation_do_call(sender, sender_pid, {:withdraw, sender, amount, currency})},
      {:deposit, {:ok, receiver_balance}} <-
        {:deposit, execute_operation_do_call(receiver, receiver_pid, {:deposit, receiver, amount, currency})}
    do
      {:ok, sender_balance, receiver_balance}
    else
      {:deposit, deposit_error} ->
        execute_operation_do_call(sender, sender_pid, {:deposit, sender, amount, currency})
        deposit_error
      {_action, error} -> error
    end
  end
end
