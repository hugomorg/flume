# Flume

This library is meant to help with managing control flow, when there are lots of steps and some may go wrong. You have probably seen or tried something with `with` statements like this:

```elixir
defmodule YourModule do
  def call(id) do
    with
      {:rates, {:ok, rates}} <- {:rates, fetch_rates()},
      {:tax, {:ok, tax}} <- {:tax, fetch_tax()},
      {:user, {:ok, user}} <- {:user, get_user(id)},
      {:items, {:ok, items}} <- {:items, get_user_items(user)} do
      # do something
    else
      {:rates, {:error, error}} -> handle_error({:rates, error})
      {:tax, {:error, error}} -> handle_error({:tax, error})
      {:user, {:error, error}} -> handle_error({:user, error})
      {:items, {:error, error}} -> handle_error({:items, error})
    end
  end

  def handle_error(error) do
    # do something
  end

  def get_user(id) do
    UserApi.get(id)
  end

  def get_user_items(user) do
    ItemApi.all(user)
  end

  def fetch_rates do
    RatesApi.call()
  end

  def fetch_tax do
    TaxApi.call()
  end
end
```

but that can easily get out of hand. `flume` allows you to do something which is arguably clearer:

```elixir
defmodule YourModule do
  def call(id) do
    Flume.new()
    |> Flume.run_async(&fetch_rates/0)
    |> Flume.run_async(&fetch_tax/0)
    |> Flume.run(fn -> get_user(id) end)
    |> Flume.run(fn %{user: user} -> get_user_items(user) end)
    |> Flume.result()
    |> case do
      {:error, errors, _changes} -> handle_error(errors)
      {:ok, results} -> # do something
    end
  end
end
```

All that it asks is that your callbacks return predictable tuples, either `{:ok, result}` or `{:error, reason}`. It will stop at the first error and nothing later will be executed - unless `run_async` is used. See the docs for more info.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `flume` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flume, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/flume](https://hexdocs.pm/flume).

