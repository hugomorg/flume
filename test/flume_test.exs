defmodule FlumeTest do
  use ExUnit.Case
  doctest Flume

  test "new/0 returns empty struct" do
    assert Flume.new() == %Flume{results: %{}, errors: %{}, halted: false}
  end

  describe "run" do
    test "run/3 executes callback and result accumulated" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn _ -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)

      assert flume == %Flume{results: %{a: 2, b: 4}, errors: %{}, halted: false}
    end

    test "run/3 stops at first error" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn _ -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)
        |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
        |> Flume.run(:this_wont_run, fn _ -> raise "boom" end)

      assert flume == %Flume{
               results: %{a: 2, b: 4},
               errors: %{this_fails: :for_some_reason},
               halted: true
             }
    end
  end
end
