defmodule MultiplayerFabricDeploy.Runner do
  alias MultiplayerFabricDeploy.Config

  @doc """
  Spawns a task asynchronously. `task.run` is either:
    - `{:bash, script}` — runs a bash script
    - `{:elixir, fun}` — calls `fun.(parent)` directly

  Sends to `parent`:
    {:output_line, String.t()}
    {:task_done, exit_code :: non_neg_integer()}
  """
  def start_async(%{run: {:bash, script}}, parent) do
    env_list =
      Config.env_vars()
      |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    spawn(fn -> run_bash(script, env_list, parent) end)
  end

  def start_async(%{run: {:elixir, fun}}, parent) do
    spawn(fn ->
      try do
        fun.(parent)
      rescue
        e ->
          send(parent, {:output_line, "Error: #{Exception.message(e)}"})
          send(parent, {:task_done, 1})
      end
    end)
  end

  defp run_bash(script, env_list, parent) do
    bash = System.find_executable("bash") || "/bin/bash"

    port =
      Port.open(
        {:spawn_executable, bash},
        [
          :binary,
          :exit_status,
          {:line, 4096},
          {:env, env_list},
          {:args, ["-c", script]}
        ]
      )

    stream_output(port, parent)
  end

  defp stream_output(port, parent) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        line |> String.split("\r") |> List.last() |> then(&send(parent, {:output_line, &1}))
        stream_output(port, parent)

      {^port, {:data, {:noeol, partial}}} ->
        partial |> String.split("\r") |> List.last() |> then(&send(parent, {:output_line, &1}))
        stream_output(port, parent)

      {^port, {:exit_status, code}} ->
        send(parent, {:task_done, code})
    end
  end
end
