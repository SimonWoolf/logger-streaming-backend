defmodule LoggerStreamingBackend.Mixfile do
  use Mix.Project

  def project do
    [app: :logger_streaming_backend,
     version: "0.1.0",
     elixir: "~> 1.3", # due to use of `with` with else clause
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     source_url: "https://github.com/SimonWoolf/logger-streaming-backend",
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp description do
    "A backend for the Elixir Logger that streams logs over HTTP, with per-stream log level and filtering based on metadata"
  end

  defp package do
    [
      maintainers: ["Simon Woolf, simon@simonwoolf.net"],
      licenses: ["LGPL3+"],
      links: %{
        "github" => "https://github.com/SimonWoolf/logger-streaming-backend"
      }
    ]
  end

  defp deps do
    [
      {:temple, "~> 0.6.0-alpha.4"},
      {:cowboy, "~> 1.0"},
      # dev deps
      {:ex_doc, "~> 0.15", only: :dev, runtime: false},
      # test deps
      {:httpoison, "~> 0.11.2", only: :test},
    ]
  end
end
