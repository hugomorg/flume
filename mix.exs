defmodule Flume.MixProject do
  use Mix.Project

  def project do
    [
      app: :flume,
      version: "1.0.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Simple, pipelined control flow for complex and dependent operations",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/HPJM/flume"}
      ],
      docs: [
        source_ref: "master",
      ],
      source_url: "https://github.com/HPJM/flume"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
