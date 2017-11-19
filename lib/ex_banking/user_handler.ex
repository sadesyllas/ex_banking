defmodule ExBanking.UserHandler do
  @moduledoc """
  This module implements the public API of ExBanking.

  Its private API is implemented in the ExBanking.UserHandler.Backend module.

  For more information, please read the `ExBanking.UserHandler` section
  in file `README.md`.
  """

  @type banking_error :: ExBanking.banking_error

  require Logger

  use GenServer

  alias ExBanking.UserHandler.Backend

  def init(_) do
    {:ok, %{}}
  end

  ##############
  # PUBLIC API #
  ##############

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
    Backend.execute_operation(user, {:deposit, user, amount, currency})
  end

  @spec withdraw(user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, new_balance :: number} | banking_error
  def withdraw(user, amount, currency) do
    Backend.execute_operation(user, {:withdraw, user, amount, currency})
  end

  @spec get_balance(user :: String.t, currency :: String.t)
    :: {:ok, balance :: number} | banking_error
  def get_balance(user, currency) do
    Backend.execute_operation(user, {:get_balance, user, currency})
  end

  @spec send(from_user :: String.t, to_user :: String.t, amount :: number, currency :: String.t)
    :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
  def send(from_user, to_user, amount, currency) do
    Backend.send(from_user, to_user, amount, currency)
  end

  #################
  # GenServer API #
  #################

  def handle_call({:deposit, user, amount, currency}, _from, state) do
    deposit_result = Backend.deposit(user, amount, currency)
    state = Map.put(state, :last_request, DateTime.utc_now())
    {:reply, deposit_result, state}
  end

  def handle_call({:withdraw, user, amount, currency}, _from, state) do
    withdraw_result = Backend.withdraw(user, amount, currency)
    state = Map.put(state, :last_request, DateTime.utc_now())
    {:reply, withdraw_result, state}
  end

  def handle_call({:get_balance, user, currency}, _from, state) do
    balance_result = Backend.get_balance(user, currency)
    state = Map.put(state, :last_request, DateTime.utc_now())
    {:reply, balance_result, state}
  end

  @doc """
  This gets called for newly created user handler processes.

  It initiates the process's state with a :last_request DateTime
  so that we can later check whether this process has been used recently.

  It the process becomes state, it is gracefully shut down.
  """
  def handle_cast(:init, state) do
    Backend.schedule_stale_check()
    state = Map.put(state, :last_request, DateTime.utc_now())
    {:noreply, state}
  end


  @doc """
  This performs the actual stale process check, as descbibed above.
  """
  def handle_info(:stale_check, %{last_request: last_request} = state) do
    Logger.debug("Checking for stale user handler process")
    timestamp_now = DateTime.to_unix(DateTime.utc_now)
    timestamp_last_request = DateTime.to_unix(last_request)
    # 1 hour in seconds
    stale_handler_timeout_seconds = Application.get_env(:ex_banking, :config)[:stale_handler_timeout_seconds] || 3600
    if timestamp_now - timestamp_last_request >= stale_handler_timeout_seconds do
      Logger.debug("Shuting down stale user handler")
      {:stop, :shutdown, state}
    else
      Backend.schedule_stale_check()
      {:noreply, state}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
