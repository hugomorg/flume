defmodule FlumeTest do
  use ExUnit.Case
  doctest Flume

  test "greets the world" do
    assert Flume.hello() == :world
  end
end
