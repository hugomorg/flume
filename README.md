# Flume

This library is meant to help with managing control flow, when there are lots of steps and some may go wrong. You have probably seen or tried something complex along these lines with `with` statements. Most of the time, they work great.

Let's use a hypothetical example that's not too far from the real world. Let's say you are processing an order from a customer in another country. You need to retrieve some information from a database, get an fx rate, get tax rates for that country, process the order, and finally store the result. Anything could fail too, so you have to annotate operations so you know which one failed. Using `with`, it may look something like this:

```elixir
defmodule MyApp.Orders do
  def process(order) do
    with {:customer, {:ok, customer}} <- {:customer, MyApp.Customers.get(order)},
         {:tax, {:ok, tax}} <- {:tax, MyApp.Tax.rate(order)},
         {:fx_rate, {:ok, fx_rate}} <- {:fx_rate, MyApp.Fx.rate(order)},
         {:payment, {:ok, items}} <- {:payment, MyApp.Payments.process(order, tax, fx_rate)},
         {:order, {:ok, order}} <- {:order, create(order, customer, tax, fx_rate)} do
      order.id
    else
      {:customer, {:error, error}} -> handle_error(:customer, error)
      {:tax, {:error, error}} -> handle_error(:tax, error)
      {:fx_rate, {:error, error}} -> handle_error(:fx_rate, error)
      {:payment, {:error, error}} -> handle_error(:payment, error)
      {:order, {:error, error}} -> handle_error(:order, error)
    end
  end

  defp handle_error(step, error) do
    # do something
  end

  def create(order, customer, tax, fx_rate) do
    # do something
  end
end
```

That can easily get out of hand and become hard to reason about. `flume` allows you to do something which is arguably clearer and more succinct:

```elixir
defmodule MyApp.Orders do
  import Flume

  def process(order) do
    Flume.new(on_error: &handle_error/2)
    |> run_async(:customer, fn -> MyApp.Customers.get(order) end)
    |> run_async(:tax, fn -> MyApp.Tax.rate(order) end)
    |> run_async(:fx_rate, fn -> MyApp.Fx.rate(order) end)
    |> run(:payment, &handle_payment(&1, order), wait_for: [:customer, :tax, :fx_rate])
    |> run(:order, &handle_order(&1, order), on_success: &Map.fetch!(&1, :id))
    |> result()
  end

  defp handle_payment(%{fx_rate: fx_rate, tax: tax}, order) do
    MyApp.Payments.process(order, tax, fx_rate)
  end

  defp handle_order(%{fx_rate: fx_rate, tax: tax, customer: customer}, order) do
    create(order, customer, tax, fx_rate)
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
