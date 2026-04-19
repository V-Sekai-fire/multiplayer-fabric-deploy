defmodule MultiplayerFabricDeploy.Runner do
  alias MultiplayerFabricDeploy.Config

  @doc """
  Spawns a bash script asynchronously. Sends messages to `parent`:
    {:output_line, String.t()}
    {:task_done, exit_code :: non_neg_integer()}
  """
  def start_async(script, parent) do
    env_list =
      Config.env_vars()
      |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    spawn(fn -> execute(script, env_list, parent) end)
  end

  defp execute(script, env_list, parent) do
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
        send(parent, {:output_line, line})
        stream_output(port, parent)

      {^port, {:data, {:noeol, partial}}} ->
        send(parent, {:output_line, partial})
        stream_output(port, parent)

      {^port, {:exit_status, code}} ->
        send(parent, {:task_done, code})
    end
  end
end
