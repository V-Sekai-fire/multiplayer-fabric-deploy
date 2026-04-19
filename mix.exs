defmodule MultiplayerFabricDeploy.MixProject do
  use Mix.Project

  def project do
    [
      app: :multiplayer_fabric_deploy,
      version: "0.3.0",
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
      {:ex_ratatui, "~> 0.7"}
    ]
  end
end
