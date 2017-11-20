defmodule ExBanking.UserHandler do
  @moduledoc """
  This module implements the public API of ExBanking.

  Its private API is implemented in the ExBanking.UserHandler.Backend module.

  For more information, please read the `ExBanking.UserHandler` section
  in file `README.md`.
  """

  @type banking_error :: ExBanking.banking_error

  require Logger

  alias ExBanking.UserHandler.Backend

  @doc """
  Creating user is simple setting her/his backlog to 0
  """
  @spec create_user(user :: String.t) :: :ok | banking_error
  def create_user(user) do
    if :ets.insert_new(:backlog, {user, 0}) do
      :ok
    else
      {:error, :user_already_exists}
    end
  end

  @spec deposit(user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, new_balance :: number} | banking_error
  def deposit(user, amount, currency) do
    Backend.execute_operation(user, fn -> Backend.deposit(user, amount, currency) end)
  end

  @spec withdraw(user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, new_balance :: number} | banking_error
  def withdraw(user, amount, currency) do
    Backend.execute_operation(user, fn -> Backend.withdraw(user, amount, currency) end)
  end

  @spec get_balance(user :: String.t, currency :: String.t)
    :: {:ok, balance :: number} | banking_error
  def get_balance(user, currency) do
    Backend.execute_operation(user, fn -> Backend.get_balance(user, currency) end)
  end

  @spec send(from_user :: String.t, to_user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
  def send(from_user, to_user, amount, currency) do
    Backend.send(from_user, to_user, amount, currency)
  end
end
