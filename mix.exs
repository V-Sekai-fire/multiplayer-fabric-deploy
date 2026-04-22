defmodule MultiplayerFabricDeploy.MixProject do
  use Mix.Project

  def project do
    [
      app: :multiplayer_fabric_deploy,
      version: "0.4.10",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      config_path: "./config/config.exs",
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [mod: {MultiplayerFabricDeploy, []}, extra_applications: [:logger]]
  end

  defp releases do
    [
      multiplayer_fabric_deploy: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux: [os: :linux, cpu: :x86_64] ++ linux_erts()
          ]
        ]
      ]
    ]
  end

  # setup-beam installs a 4-segment OTP version (e.g. 27.3.4.11) that Burrito's
  # CDN does not carry. CI pre-downloads a 3-segment tarball and sets this env var.
  defp linux_erts do
    case System.get_env("BURRITO_CUSTOM_ERTS") do
      nil -> []
      path -> [custom_erts: path]
    end
  end

  defp deps do
    [
      {:ex_ratatui, "~> 0.7"},
      {:egit, "~> 0.1"},
      {:taskweft, path: "../multiplayer-fabric-taskweft"},
      {:burrito, "~> 1.5"}
    ]
  end
end
