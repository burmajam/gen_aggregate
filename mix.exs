defmodule Aggregate.Mixfile do
  use Mix.Project

  def project do
    [app: :aggregate,
     version: "0.0.5",
     elixir: "~> 1.2",
     package: package(),
     description: description(),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application, do: [applications: [:logger]]

  defp deps do 
    [
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp package do
    %{
       maintainers: ["Milan Burmaja"],
       links: %{ "GitHub" => "https://github.com/burmajam/gen_aggregate"},
       licenses: ["MIT"],
       files: ~w(lib mix.exs README*) }
  end

  defp description do
    """
    Aggregate from DDD. Perfect fit with Extreme project
    """
  end
end
