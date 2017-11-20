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
          {:backlog1, :ok} <- {:backlog1, try_add_backlog(sender)},
          {:backlog2, :ok} <- {:backlog2, try_add_backlog(receiver)} do
        result = do_send(sender, receiver, amount, currency)
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
  Make sure that the user exists before we do any transfers.
  """
  @spec execute_operation(user :: binary, operation :: tuple)
    :: success :: term | banking_error
  def execute_operation(user, fun) do
    with :ok <- exists?(user),
         :ok <- try_add_backlog(user) do
      result = fun.()
      remove_backlog(user)
      result
    end
  end

  @doc """
  Part of send which does the actual money tranfers.
  """
  @spec do_send(sender :: binary, receiver :: binary, amount :: float, currency :: binary)
    :: {:ok, new_sender_balance :: float, new_receiver_balance :: float} | banking_error
  defp do_send(sender, receiver, amount, currency) do
    with\
      {:withdrawal, {:ok, sender_balance}} <- {:withdrawal, withdraw(sender, amount, currency)},
      {:deposit, {:ok, receiver_balance}} <- {:deposit, deposit(receiver, amount, currency)}
    do
      if sender === receiver do
        {:ok, receiver_balance, receiver_balance}
      else
        {:ok, sender_balance, receiver_balance}
      end
    else
      {:deposit, deposit_error} ->
        deposit(sender, amount, currency)
        deposit_error
      {_action, error} -> error
    end
  end
end
