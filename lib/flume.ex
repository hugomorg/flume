defmodule Flume do
  @moduledoc """
  A convenient way to handle control flow in pipelines. This makes for easier reading and composability.
  """

  @type t :: %__MODULE__{}
  @type tag :: atom()
  @type callback_fun :: (map() -> {:ok, tag()} | {:error, atom()})

  defstruct results: %{}, errors: %{}, halted: false

  @doc """
  Returns empty Flume struct.

  ## Examples

      iex> Flume.new()
      %Flume{}

  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Executes passed in callback synchronously - and stores the returned result.

  Callback has to be a 1-arity function, and is passed the current accumulated results.
  It must return a `{:ok, result}` or a `{:error, reason}` tuple. In the first case,
  the result will be added to the accumulator, and in the second case the error will be stored.

  A tag annotates the operation.

  ## Examples

      Flume.new()
      |> Flume.run(:a, fn _ -> {:ok, 2} end)
      |> Flume.run(:b, fn data -> {:ok, 2 * data.a} end)
      |> Flume.run(:this_fails, fn _ -> {:error, :for_some_reason} end)
      |> Flume.run(:this_wont_run, fn _ -> raise "boom" end)

  """
  @spec run(t(), tag(), callback_fun) :: t()
  def run(%Flume{halted: true} = flume, _tag, _fun), do: flume

  def run(%Flume{results: results, errors: errors} = flume, tag, fun)
      when is_atom(tag) and is_function(fun, 1) do
    case fun.(results) do
      {:ok, result} ->
        results = Map.put(results, tag, result)
        %Flume{flume | results: results}

      {:error, error} ->
        errors = Map.put(errors, tag, error)
        %Flume{flume | errors: errors, halted: true}

      bad_match ->
        raise "Expected either an `{:ok, result}` or {:error, reason} tuple, but got #{
                inspect(bad_match)
              }"
    end
  end
end
