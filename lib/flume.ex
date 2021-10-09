defmodule Flume do
  @moduledoc """
  A convenient way to handle control flow in pipelines. This makes for easier reading and composability.
  """

  @type t :: %__MODULE__{}
  @type tag :: atom()
  @type process_fun :: (map() -> {:ok, tag()} | {:error, atom()})

  defstruct [:halt_on_errors, results: %{}, errors: %{}, halted: false, tasks: []]

  @doc """
  Returns empty Flume struct.

  Options:

  - `:halt_on_errors`: if false, `flume` won't stop if `Flume.run` matches an error

  ## Examples

      iex> Flume.new()
      %Flume{halt_on_errors: true}

  """
  @spec new(list()) :: t()
  def new(opts \\ []) do
    halt_on_errors = Keyword.get(opts, :halt_on_errors, true)
    %__MODULE__{halt_on_errors: halt_on_errors}
  end

  @doc """
  Executes passed in callback synchronously - and stores the returned result.

  Callback has to be a 0- or 1-arity function, and if it accepts an argument it is passed
  the current accumulated results.

  It must return a `{:ok, result}` or a `{:error, reason}` tuple. In the first case,
  the result will be added to the accumulator, and in the second case the error will be stored.

  A tag annotates the operation.

  Several options can be passed in:
  - `on_success`: 1 or 2 arity callback which is given the result of the operation if successful,
  or the tag and the result. The return value is stored in the results
  - `on_error`: 1 or 2 arity callback which is given the error reason of the operation if it failed,
  or the tag and the error

  ## Examples

      Flume.new()
      |> Flume.run(:a, fn _ -> {:ok, 2} end)
      |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end, on_success: fn n -> n * 100 end)
      |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
      |> Flume.run(:this_wont_run, fn _ -> raise "boom" end)

  """
  @spec run(t(), tag(), process_fun(), list()) :: t()
  def run(flume, tag, process_fun, opts \\ [])

  def run(%Flume{halted: true, halt_on_errors: true} = flume, _tag, _process_fun, _opts),
    do: flume

  def run(%Flume{results: results, errors: errors} = flume, tag, process_fun, opts)
      when is_atom(tag) and (is_function(process_fun, 1) or is_function(process_fun, 0)) do
    on_success = Keyword.get(opts, :on_success)
    on_error = Keyword.get(opts, :on_error)

    case apply_process_callback(process_fun, results) do
      {:ok, result} ->
        result = maybe_apply_on_success(on_success, result, tag)
        results = Map.put(results, tag, result)
        %Flume{flume | results: results}

      {:error, error} ->
        maybe_apply_on_error(on_error, error, tag)
        errors = Map.put(errors, tag, error)
        %Flume{flume | errors: errors, halted: true}

      bad_match ->
        match_error(tag, bad_match)
    end
  end

  @doc """
  Executes passed in callback asynchronously - and stores the returned result. All asynchronous
  operations are resolved when `Flume.result/1` is called.

  Apart from the asynchronous nature of this function, it behaves in the same with as `Flume.run`.

  Obviously using this in combination with `Flume.run` is less safe, because it won't necessarily stop
  at the first error. Also the results of the asynchronous operations will not be available until the end.

  ## Examples

      Flume.new()
      |> Flume.run(:a, fn -> {:ok, 2} end)
      |> Flume.run_async(:b, fn data -> {:ok, data.a * 2} end)
      |> Flume.run_async(:c, fn -> {:ok, 4} end, on_success: & &1 * 2)
      |> Flume.result()

  """
  @spec run_async(t(), tag(), process_fun(), list()) :: t()
  def run_async(flume, tag, process_fun, opts \\ [])

  def run_async(
        %Flume{halted: true, halt_on_errors: true} = flume,
        _tag,
        _process_fun,
        _opts
      ),
      do: flume

  def run_async(%Flume{tasks: tasks} = flume, tag, process_fun, opts)
      when is_atom(tag) and is_function(process_fun, 0) do
    on_success = Keyword.get(opts, :on_success)
    on_error = Keyword.get(opts, :on_error)

    task_fun = fn -> {tag, process_fun.(), on_success, on_error} end
    %Flume{flume | tasks: [Task.async(task_fun) | tasks]}
  end

  def run_async(%Flume{tasks: tasks, results: results} = flume, tag, process_fun, opts)
      when is_atom(tag) and is_function(process_fun, 1) do
    on_success = Keyword.get(opts, :on_success)
    on_error = Keyword.get(opts, :on_error)

    task_fun = fn -> {tag, process_fun.(results), on_success, on_error} end
    %Flume{flume | tasks: [Task.async(task_fun) | tasks]}
  end

  @doc """
  Returns result of pipeline.

  ## Examples

      iex> Flume.new() |> Flume.run(:a, fn -> {:ok, 2} end) |> Flume.result()
      {:ok, %{a: 2}}

      iex> Flume.new() |> Flume.run(:a, fn -> {:error, :idk} end) |> Flume.result()
      {:error, %{a: :idk}, %{}}
  """
  @spec result(Flume.t()) :: {:ok, map()} | {:error, map(), map()}
  def result(%Flume{results: results, errors: errors, tasks: []}) when map_size(errors) == 0 do
    {:ok, results}
  end

  def result(%Flume{results: results, errors: errors, tasks: []}) do
    {:error, errors, results}
  end

  def result(%Flume{} = flume) do
    resolved = resolve_tasks(flume)
    flume |> merge_results(resolved) |> Map.put(:tasks, []) |> result()
  end

  defp maybe_apply_on_success(_fun = nil, result, _tag), do: result
  defp maybe_apply_on_success(fun, result, _tag) when is_function(fun, 1), do: fun.(result)
  defp maybe_apply_on_success(fun, result, tag) when is_function(fun, 2), do: fun.(tag, result)

  defp maybe_apply_on_error(_fun = nil, error, _tag), do: error

  defp maybe_apply_on_error(fun, error, _tag) when is_function(fun, 1) do
    fun.(error)
    error
  end

  defp maybe_apply_on_error(fun, error, tag) when is_function(fun, 2) do
    fun.(tag, error)
    error
  end

  defp resolve_tasks(%Flume{tasks: tasks}) do
    tasks
    |> Task.await_many()
    |> Enum.map(fn
      {tag, {:ok, result}, success_fun, _error_fun} ->
        result = maybe_apply_on_success(success_fun, result, tag)
        {:results, {tag, result}}

      {tag, {:error, reason}, _success_fun, error_fun} ->
        maybe_apply_on_error(error_fun, reason, tag)
        {:errors, {tag, reason}}

      {tag, bad_match, _success_fun, _error_fun} ->
        match_error(tag, bad_match)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {k, v} -> {k, Map.new(v)} end)
    |> Enum.into(%{})
  end

  defp merge_results(%Flume{results: results, errors: errors} = flume, %{
         results: task_results,
         errors: task_errors
       }) do
    %Flume{
      flume
      | results: Map.merge(results, task_results),
        errors: Map.merge(errors, task_errors)
    }
  end

  defp merge_results(%Flume{results: results} = flume, %{results: task_results}) do
    %Flume{flume | results: Map.merge(results, task_results)}
  end

  defp merge_results(%Flume{errors: errors} = flume, %{errors: task_errors}) do
    %Flume{flume | errors: Map.merge(errors, task_errors)}
  end

  defp apply_process_callback(callback, results) when is_function(callback, 1) do
    callback.(results)
  end

  defp apply_process_callback(callback, _results) do
    callback.()
  end

  defp match_error(tag, bad_match) do
    raise "#{tag}: Expected either an `{:ok, result}` or `{:error, reason}` tuple " <>
            "from the process callback but got #{inspect(bad_match)}"
  end
end
