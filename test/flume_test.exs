defmodule FlumeTest do
  use ExUnit.Case
  require Logger
  doctest Flume

  test "new/0 returns empty struct" do
    assert Flume.new() == %Flume{results: %{}, errors: %{}, halted: false, halt_on_errors: true}
  end

  describe "result returns result of pipeline" do
    test "result/1 returns ok tuple if no errors" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.result()

      assert flume == {:ok, %{a: 2}}
    end

    test "result/1 returns error tuple if any error" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
        |> Flume.result()

      assert flume == {:error, %{this_fails: :for_some_reason}, %{a: 2}}
    end
  end

  describe "run" do
    test "run/3 executes callback and result accumulated" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)

      assert flume.results == %{a: 2, b: 4}
      assert flume.errors == %{}
    end

    test "run/3 stops at first error by default" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)
        |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
        |> Flume.run(:this_wont_run, fn _ -> raise "boom" end)

      assert flume.results == %{a: 2, b: 4}
      assert flume.errors == %{this_fails: :for_some_reason}
      assert flume.halted
    end

    test "run/3 doesn't at first error if `:halt_on_errors` specified" do
      flume =
        Flume.new(halt_on_errors: false)
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)
        |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
        |> Flume.run(:this_is, fn _ -> {:error, :another_error} end)

      assert flume.results == %{a: 2, b: 4}
      assert flume.errors == %{this_fails: :for_some_reason, this_is: :another_error}
      assert flume.halted
    end

    test "run/4 processes result in success case with on_success callback" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end, on_success: &(&1 * 100))

      assert flume.results == %{a: 2, b: 400}
      assert flume.errors == %{}
    end

    test "run/4 processes error in failure case with on_error callback" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          flume =
            Flume.new()
            |> Flume.run(:a, fn -> {:ok, 2} end)
            |> Flume.run(:b, fn -> {:error, :for_some_reason} end,
              on_error: &Logger.error("Operation failed #{&1}")
            )
            |> Flume.result()

          assert {:error, _, _} = flume
        end)

      assert log =~ "Operation failed for_some_reason"
    end

    test "run/4 wait_for option awaits async tasks so that they are accessible in callback" do
      flume =
        Flume.new()
        |> Flume.run_async(:a, fn ->
          :timer.sleep(1)
          {:ok, :ready}
        end)
        |> Flume.run(:b, fn %{a: :ready} -> {:ok, :waited} end, wait_for: [:a])

      assert flume.results == %{a: :ready, b: :waited}
      assert flume.tasks == %{}
      assert flume.errors == %{}
    end
  end

  describe "run_async" do
    test "run_async/3 concurrently executes functions and resolves results at end" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run_async(:b, fn data -> {:ok, data.a * 2} end)
        |> Flume.run_async(:c, fn -> {:ok, 4} end, on_success: &(&1 * 2))
        |> Flume.result()

      assert flume == {:ok, %{a: 2, b: 4, c: 8}}
    end

    test "run_async/3 concurrently executes functions and resolves errors at end" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run_async(:b, fn data -> {:ok, data.a * 2} end)
        |> Flume.run_async(:c, fn -> {:ok, 4} end, on_success: &(&1 * 2))
        |> Flume.run_async(:d, fn -> {:error, :fail} end)
        |> Flume.result()

      assert flume == {:error, %{d: :fail}, %{a: 2, b: 4, c: 8}}
    end
  end
end
