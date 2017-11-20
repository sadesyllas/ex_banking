defmodule ExBankingTest do
  use ExUnit.Case, async: false

  alias ExBanking.UserHandler.Backend

  test "user creation with a wrong argument fails" do
    results =
      [
        ExBanking.create_user(nil),
        ExBanking.create_user(123),
        ExBanking.create_user({}),
        ExBanking.create_user([]),
        ExBanking.create_user(%{}),
        ExBanking.create_user('test_user'),
        ExBanking.create_user(""),
      ]

    assert Enum.count(results, fn result -> result === {:error, :wrong_arguments} end) === Enum.count(results)
  end

  test "deposit calls with a wrong argument fail" do
    results =
      [
        ExBanking.deposit("", 5, "EUR"),
        ExBanking.deposit("foo", 2, 123),
        ExBanking.deposit("foo", -2, "bar"),
      ]

    assert Enum.count(results, fn result -> result === {:error, :wrong_arguments} end) === Enum.count(results)
  end

  test "withdrawal calls with a wrong argument fail" do
    results =
      [
        ExBanking.withdraw("", 5, "EUR"),
        ExBanking.withdraw("foo", 2, 123),
        ExBanking.withdraw("foo", -2, "bar"),
      ]

    assert Enum.count(results, fn result -> result === {:error, :wrong_arguments} end) === Enum.count(results)
  end

  test "get_balance calls with a wrong argument fail" do
    results =
      [
        ExBanking.get_balance(nil, "EUR"),
        ExBanking.get_balance(123, "EUR"),
        ExBanking.get_balance({}, "EUR"),
        ExBanking.get_balance([], "EUR"),
        ExBanking.get_balance(%{}, "EUR"),
        ExBanking.get_balance('test_user', "EUR"),
        ExBanking.get_balance("", "EUR"),
        ExBanking.get_balance("foo", nil),
        ExBanking.get_balance("foo", ""),
      ]

    assert Enum.count(results, fn result -> result === {:error, :wrong_arguments} end) === Enum.count(results)
  end

  test "send calls with a wrong argument fail" do
    results =
      [
        ExBanking.send("", "bar", 5, "EUR"),
        ExBanking.send("foo", "", 5, "EUR"),
        ExBanking.send("foo", "bar", 2, 123),
        ExBanking.send("foo", "bar", -2, "EUR"),
      ]

    assert Enum.count(results, fn result -> result === {:error, :wrong_arguments} end) === Enum.count(results)
  end

  test "user creation works" do
    assert ExBanking.create_user("test_user") === :ok
    assert ExBanking.create_user("retest_user") === :ok
  end

  test "trying to create an already created user fails" do
    assert ExBanking.create_user("test_user") === {:error, :user_already_exists}
    assert ExBanking.create_user("retest_user") === {:error, :user_already_exists}
  end

  test "user existence check works" do
    assert Backend.exists?("test_user") === :ok
    assert Backend.exists?("not_me") === {:error, :user_does_not_exist}
  end

  test "withdrawal from a non existent account fails" do
    assert ExBanking.withdraw("not_me", 10, "EUR") === {:error, :user_does_not_exist}
  end

  test "withdrawal from an account with no money fails" do
    assert ExBanking.withdraw("test_user", 10, "EUR") === {:error, :not_enough_money}
  end

  test "deposit to a non existent account fails" do
    assert ExBanking.deposit("not_me", 10, "EUR") === {:error, :user_does_not_exist}
  end

  test "deposit to an existent account succeeds" do
    assert ExBanking.deposit("retest_user", 10, "EUR") === {:ok, 10.0}
    assert ExBanking.deposit("test_user", 10, "EUR") === {:ok, 10.0}
  end

  test "withdrawal from an account with not enough money fails" do
    assert ExBanking.withdraw("test_user", 11, "EUR") === {:error, :not_enough_money}
  end

  test "withdrawal from an account with enough money succeeds" do
    assert ExBanking.withdraw("test_user", 4, "EUR") === {:ok, 6.0}
  end

  test "the backlog is rate limited to 10 operations at any time for a specific user" do
    successful_add_backlog_operations =
      1..100
      |> Enum.map(fn _ ->
        Task.async(fn -> Backend.try_add_backlog("test_user") end)
      end)
      |> Enum.map(fn task ->
        Task.await(task)
      end)
      |> Enum.count(fn result -> result !== {:error, :too_many_requests_to_user} end)

    assert successful_add_backlog_operations === 10

    Backend.remove_backlog("test_user")

    assert Backend.try_add_backlog("test_user") === :ok

    Enum.each(1..100, fn _ -> Backend.remove_backlog("test_user") end)

    assert :ets.lookup(:backlog, "test_user") === [{"test_user", 0}]
  end

  test "removing from the backlog for an inexistent user is ok" do
    assert Backend.remove_backlog("not_me") === :ok
  end

  test "sending from an inexistent user to a user fails" do
    assert ExBanking.send("not_me", "test_user", 1, "EUR") === {:error, :sender_does_not_exist}
  end

  test "sending from a user to an inexistent user fails" do
    assert ExBanking.send("test_user", "not_me", 1, "EUR") === {:error, :receiver_does_not_exist}
  end

  test "sending from a user to another user when the sender does not have enough money fails" do
    assert ExBanking.send("test_user", "retest_user", 11, "EUR") === {:error, :not_enough_money}
  end

  test "sending from a user to another user when the sender has enough money succeeds" do
    assert ExBanking.send("test_user", "retest_user", 4, "EUR") === {:ok, 2.0, 14.0}
  end

  test "sending from a user to the same user when the user has enough money succeeds" do
    assert ExBanking.send("test_user", "test_user", 2, "EUR") === {:ok, 2.0, 2.0}
  end

  test "getting the balance of a non existent user fails" do
    assert ExBanking.get_balance("not_me", "EUR") === {:error, :user_does_not_exist}
  end

  test "getting the balance of an existent user succeeds" do
    assert ExBanking.get_balance("test_user", "EUR") === {:ok, 2.0}
  end

  test "getting the balance of an existent user and a currency not used before succeeds with a balance of 0" do
    assert ExBanking.get_balance("test_user", "USD") === {:ok, 0.0}
  end

  test "setting the balance of an existent user and a currency not used before succeeds without messing up the other balances" do
    assert ExBanking.deposit("test_user", 10, "USD") === {:ok, 10.0}
    assert ExBanking.get_balance("test_user", "EUR") === {:ok, 2.0}
  end

  test "keeping the sender busy with other operations " <>
    "while trying to send yields {:error, :too_many_requests_to_sender}" do
    assert ExBanking.deposit("test_user", 1000, "EUR") === {:ok, 1002.0}

    me = self()

    spawn(fn ->
      Enum.each(1..100, fn _ -> ExBanking.deposit("test_user", 1, "EUR") end)
      send(me, :sender_busy_done)
    end)

    error_count =
      1..100
      |> Enum.map(fn _ ->
        Task.async(fn -> ExBanking.send("test_user", "retest_user", 1, "EUR") end)
      end)
      |> Enum.map(fn task ->
        Task.await(task)
      end)
      |> Enum.count(fn result -> result === {:error, :too_many_requests_to_sender} end)

    assert_receive :sender_busy_done, 5000

    assert error_count !== 0
  end

  test "keeping the receiver busy with other operations " <>
    "while trying to send yields {:error, :too_many_requests_to_receiver} " <>
    "and returns the money to the sender" do
      assert {:ok, _balance} = ExBanking.deposit("test_user", 1000, "EUR")

      {:ok, sender_balance} = ExBanking.get_balance("test_user", "EUR")

      me = self()

      spawn(fn ->
        Enum.each(1..100, fn _ -> ExBanking.deposit("retest_user", 1, "EUR") end)
        send(me, :receiver_busy_done)
      end)

      results =
        1..100
        |> Enum.map(fn _ ->
          Task.async(fn -> ExBanking.send("test_user", "retest_user", 1, "EUR") end)
        end)
        |> Enum.map(fn task ->
          Task.await(task)
        end)

      error_count = Enum.count(results, fn result ->
        result === {:error, :too_many_requests_to_sender} ||
        result === {:error, :too_many_requests_to_receiver}
      end)

      {:ok, new_sender_balance} = ExBanking.get_balance("test_user", "EUR")

      assert_receive :receiver_busy_done, 5000
      assert error_count !== 0
      assert new_sender_balance === (sender_balance - (100 - error_count))
  end
end
