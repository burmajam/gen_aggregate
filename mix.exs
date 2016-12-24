defmodule Aggregate.Mixfile do
  use Mix.Project

  def project do
    [app: :aggregate,
     version: "0.0.4",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application, do: [applications: [:logger]]

  defp deps, do: []
end
