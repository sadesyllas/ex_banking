defmodule ExBanking do
  @moduledoc """
  This module is the public API for ExBanking.

  Its sole logic is to pass the call the UserHandler module
  after performing the necessary input validation.
  """

  alias ExBanking.UserHandler

  @type banking_error :: {:error,
    :wrong_arguments               |
    :user_already_exists           |
    :user_does_not_exist           |
    :not_enough_money              |
    :sender_does_not_exist         |
    :receiver_does_not_exist       |
    :too_many_requests_to_user     |
    :too_many_requests_to_sender   |
    :too_many_requests_to_receiver }

    @spec create_user(user :: String.t) :: :ok | banking_error
    def create_user(user)
    def create_user(""), do: {:error, :wrong_arguments}
    def create_user(<<user::binary>>), do: UserHandler.create_user(user)
    def create_user(_), do: {:error, :wrong_arguments}

    @spec deposit(user :: String.t, amount :: number, currency :: String.t)
      :: {:ok, new_balance :: number} | banking_error
    def deposit(user, amount, currency)
    def deposit("", _amount, _currency), do: {:error, :wrong_arguments}
    def deposit(_user, _amount, ""), do: {:error, :wrong_arguments}
    def deposit(<<user::binary>>, amount, <<currency::binary>>)
    when is_number(amount) and amount >= 0
    do
      amount = ensure_float(amount)
      UserHandler.deposit(user, Float.round(amount, 2), currency)
    end
    def deposit(_user, _amount, _currency), do: {:error, :wrong_arguments}

    @spec withdraw(user :: String.t, amount :: number, currency :: String.t)
      :: {:ok, new_balance :: number} | banking_error
    def withdraw(user, amount, currency)
    def withdraw("", _amount, _currency), do: {:error, :wrong_arguments}
    def withdraw(_user, _amount, ""), do: {:error, :wrong_arguments}
    def withdraw(<<user::binary>>, amount, <<currency::binary>>)
    when is_number(amount) and amount >= 0
    do
      amount = ensure_float(amount)
      UserHandler.withdraw(user, Float.round(amount, 2), currency)
    end
    def withdraw(_user, _amount, _currency), do: {:error, :wrong_arguments}

    @spec get_balance(user :: String.t, currency :: String.t)
      :: {:ok, balance :: number} | banking_error
    def get_balance(user, currency)
    def get_balance("", _currency), do: {:error, :wrong_arguments}
    def get_balance(_user, ""), do: {:error, :wrong_arguments}
    def get_balance(<<user::binary>>, <<currency::binary>>), do: UserHandler.get_balance(user, currency)
    def get_balance(_user, _currency), do: {:error, :wrong_arguments}

    @spec send(from_user :: String.t, to_user :: String.t, amount :: number, currency :: String.t)
      :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
    def send(from_user, to_user, amount, currency)
    def send("", _to_user, _amount, _currency), do: {:error, :wrong_arguments}
    def send(_from_user, "", _amount, _currency), do: {:error, :wrong_arguments}
    def send(_from_user, _to_user, _amount, ""), do: {:error, :wrong_arguments}
    def send(<<from_user::binary>>, <<to_user::binary>>, amount, <<currency::binary>>)
    when is_number(amount) and amount >= 0
    do
      amount = ensure_float(amount)
      UserHandler.send(from_user, to_user, Float.round(amount, 2), currency)
    end
    def send(_from_user, _to_user, _amount, _currency), do: {:error, :wrong_arguments}

    @spec ensure_float(amount :: number) :: float
    defp ensure_float(amount) do
      if is_float(amount) do
        amount
      else
        amount |> to_string() |> Float.parse() |> elem(0)
      end
    end
end
