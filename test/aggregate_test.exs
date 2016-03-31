defmodule AggregateTest do
  use ExUnit.Case, async: true
  doctest Aggregate

  setup do
    {:ok, a} = Aggregate.start_link
    {:ok, %{a: a}}
  end

  test "can commit active transaction", %{a: a} do
    {:ok, transaction_id, events} = Aggregate.do_something(a, "something")
    :ok = Aggregate.commit a, transaction_id, events
    assert Aggregate.message(a) == "something"
  end

  test "can't commit nil transaction", %{a: a} do
    assert {:error, :nil_transaction} =  Aggregate.commit(a, nil, [])
  end

  test "can't commit wrong transaction", %{a: a} do
    {:ok, _, events} = Aggregate.do_something(a, "something")
    assert {:error, :wrong_transaction} =  Aggregate.commit(a, :wrong_transaction, events)
  end

  test "waits with second command until first is commited", %{a: a} do
    for n <- 1..5 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, events_2} = Aggregate.do_something(a, "#{n} ")
        :timer.sleep n * 100
        :ok = Aggregate.commit a, transaction_id_2, events_2
      end
    end
    :timer.sleep 10
    {:ok, transaction_id_1, events_1} = Aggregate.do_something(a, "else ")
    for n <- 6..9 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, events_2} = Aggregate.do_something(a, "#{n} ")
        :ok = Aggregate.commit a, transaction_id_2, events_2
      end
    end
    :ok = Aggregate.commit a, transaction_id_1, events_1
    assert Aggregate.message(a) == "1 2 3 4 5 else 6 7 8 9 "
  end

  test "timeout", %{a: a} do
    {:ok, transaction_id_1, events_1} = Aggregate.do_something(a, "1 ")
    :ok = Aggregate.commit a, transaction_id_1, events_1
    assert Aggregate.message(a) == "1 "
    {:ok, transaction_id_3, events_3} = Aggregate.do_something(a, "throw_away")
    for n <- 2..5 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, events_2} = Aggregate.do_something(a, "#{n} ")
        :ok = Aggregate.commit a, transaction_id_2, events_2
      end
    end
    :timer.sleep 3_000
    {:error, :wrong_transaction} = Aggregate.commit a, transaction_id_3, events_3
    assert Aggregate.message(a) == "1 2 3 4 5 "
  end
end
