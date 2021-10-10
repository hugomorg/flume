defmodule FlumeTest do
  use ExUnit.Case
  require Logger
  doctest Flume

  test "new/0 returns empty struct" do
    assert Flume.new() == %Flume{
             results: %{},
             errors: %{},
             halted: false,
             halt_on_errors: true,
             global_funs: %{on_error: nil}
           }
  end

  describe "result returns result of pipeline" do
    test "result/1 returns ok tuple if no errors" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.result()

      assert flume == {:ok, %{a: 2}}
    end

    test "result/1 resolves pending tasks" do
      flume =
        %{tasks: %{a: %{task: task}}} =
        Flume.new()
        |> Flume.run_async(:a, fn -> {:ok, 2} end)

      assert task.pid in Process.list()
      assert Flume.result(flume) == {:ok, %{a: 2}}
      refute task.pid in Process.list()
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
      refute flume.halted
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

    test "run/3 doesn't stop at first error if `:halt_on_errors` specified" do
      flume =
        Flume.new(halt_on_errors: false)
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)
        |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
        |> Flume.run(:this_is, fn _ -> {:error, :another_error} end)

      assert flume.results == %{a: 2, b: 4}
      assert flume.errors == %{this_fails: :for_some_reason, this_is: :another_error}
      refute flume.halted
    end

    test "run/4 processes result in success case with on_success callback" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end, on_success: &{&1, &2})
        |> Flume.run(:b, fn -> {:ok, 4} end, on_success: &(&1 * 100))

      assert flume.results == %{a: {:a, 2}, b: 400}
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

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          flume =
            Flume.new()
            |> Flume.run(:a, fn -> {:ok, 2} end)
            |> Flume.run(:b, fn -> {:error, :for_some_reason} end,
              on_error: &Logger.error("Operation #{&1} failed #{&2}")
            )
            |> Flume.result()

          assert {:error, _, _} = flume
        end)

      assert log =~ "Operation b failed for_some_reason"
    end

    test "run/4 processes error in failure case with global on_error callback" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          flume =
            Flume.new(on_error: &Logger.error("Operation failed #{&1}"))
            |> Flume.run(:a, fn -> {:ok, 2} end)
            |> Flume.run(:b, fn -> {:error, :for_some_reason} end)
            |> Flume.result()

          assert {:error, _, _} = flume
        end)

      assert log =~ "Operation failed for_some_reason"

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          flume =
            Flume.new(on_error: &Logger.error("Operation #{&1} failed #{&2}"))
            |> Flume.run(:a, fn -> {:ok, 2} end)
            |> Flume.run(:b, fn -> {:error, :for_some_reason} end)
            |> Flume.result()

          assert {:error, _, _} = flume
        end)

      assert log =~ "Operation b failed for_some_reason"
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

    test "run/4 wait_for option when async errors out stops flume" do
      flume =
        Flume.new()
        |> Flume.run_async(:a, fn ->
          :timer.sleep(1)
          {:error, :ready}
        end)
        |> Flume.run(:b, fn -> {:should, :not_run} end, wait_for: [:a])

      assert flume.tasks == %{}
      assert flume.errors == %{a: :ready}
      assert flume.halted
    end

    test "run/4 wait_for option when async errors doesn't stop flume if halt_on_errors false" do
      flume =
        Flume.new(halt_on_errors: false)
        |> Flume.run_async(:a, fn ->
          :timer.sleep(1)
          {:error, :ready}
        end)
        |> Flume.run(:b, fn -> {:error, :another_error} end, wait_for: [:a])

      assert flume.tasks == %{}
      assert flume.errors == %{a: :ready, b: :another_error}
      refute flume.halted
    end

    test "run/3 rejects operations that don't return accepted tuples" do
      assert_raise(
        RuntimeError,
        "a: Expected either an `{:ok, result}` or `{:error, reason}` tuple from the process callback but got {:not_allowed, 2}",
        fn ->
          Flume.run(Flume.new(), :a, fn -> {:not_allowed, 2} end)
        end
      )
    end
  end

  describe "run_async" do
    test "run_async/3 concurrently executes functions and resolves results at end" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run_async(:b, fn data -> {:ok, data.a * 2} end)
        |> Flume.run_async(:c, fn -> {:ok, 8} end)
        |> Flume.result()

      assert flume == {:ok, %{a: 2, b: 4, c: 8}}
    end

    test "run_async/3 accepts optional on_success callback" do
      flume =
        Flume.new()
        |> Flume.run(:a, fn -> {:ok, 2} end)
        |> Flume.run_async(:b, fn data -> {:ok, data.a * 2} end, on_success: &"#{&1} is #{&2}")
        |> Flume.run_async(:c, fn -> {:ok, 4} end, on_success: &(&1 * 2))
        |> Flume.result()

      assert flume == {:ok, %{a: 2, b: "b is 4", c: 8}}
    end

    test "run_async/3 runs on_error callback on failure" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          flume =
            Flume.new()
            |> Flume.run(:a, fn -> {:ok, 2} end)
            |> Flume.run_async(:b, fn data -> {:error, data.a * 2} end,
              on_error: &Logger.error("Operation #{&1} failed #{&2}")
            )
            |> Flume.run_async(:c, fn -> {:error, 4} end,
              on_error: &Logger.error("Operation failed #{&1}")
            )
            |> Flume.result()

          assert flume == {:error, %{c: 4, b: 4}, %{a: 2}}
        end)

      assert log =~ "Operation b failed"
      assert log =~ "Operation failed"
    end

    test "run_async/3 runs global on_error callback on failure" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          flume =
            Flume.new(on_error: &Logger.error("Operation #{&1} failed #{&2}"))
            |> Flume.run(:a, fn -> {:ok, 2} end)
            |> Flume.run_async(:b, fn data -> {:error, data.a * 2} end)
            |> Flume.run_async(:c, fn -> {:error, 4} end)
            |> Flume.result()

          assert flume == {:error, %{c: 4, b: 4}, %{a: 2}}
        end)

      assert log =~ "Operation b failed"
      assert log =~ "Operation c failed"
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

    test "run_async/3 rejects operations that don't return accepted tuples" do
      assert_raise(
        RuntimeError,
        "a: Expected either an `{:ok, result}` or `{:error, reason}` tuple from the process callback but got {:not_allowed, 2}",
        fn ->
          Flume.new() |> Flume.run_async(:a, fn -> {:not_allowed, 2} end) |> Flume.result()
        end
      )
    end
  end
end
