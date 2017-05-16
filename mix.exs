defmodule LoggerStreamingBackend.Mixfile do
  use Mix.Project

  def project do
    [app: :logger_streaming_backend,
     version: "0.1.0",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      # ref is 0.9-dev. (eml doesn't use git tags, and last version released on hex is way old)
      {:eml, github: "zambal/eml", ref: "074f2d8619947ae075a4f742c7579610276f96c1"},
      {:cowboy, "~> 1.0"},
      # dev deps
      {:ex_doc, "~> 0.15", only: :dev, runtime: false},
      # test deps
      {:httpoison, "~> 0.11.2", only: :test},
    ]
  end
end
