defmodule MultiplayerFabricDeploy.MixProject do
  use Mix.Project

  def project do
    [
      app: :multiplayer_fabric_deploy,
      version: "0.4.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp releases do
    [
      multiplayer_fabric_deploy: [
        steps: [:assemble],
        strip_beams: true
      ]
    ]
  end

  defp deps do
    [
      {:ex_ratatui, "~> 0.7"},
      {:egit, "~> 0.1"}
    ]
  end
end
