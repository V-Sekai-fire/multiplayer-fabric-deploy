defmodule MultiplayerFabricDeploy do
  alias MultiplayerFabricDeploy.{Config, Runner, Tasks, Tui}

  def main(_args) do
    File.mkdir_p!(Config.logs_dir())

    ExRatatui.run(fn terminal ->
      state = %{
        selected: 0,
        tasks: Tasks.all(),
        log: ["Multiplayer Fabric Deploy", "Select a task and press Enter."],
        running: false,
        current_task: nil,
        quit: false
      }

      loop(terminal, state)
    end)
  end

  defp loop(terminal, state) do
    Tui.render(terminal, state)

    timeout = if state.running, do: 50, else: 5_000
    event = ExRatatui.poll_event(timeout)

    state
    |> handle_event(event)
    |> collect_output()
    |> then(fn s ->
      if s.quit, do: :ok, else: loop(terminal, s)
    end)
  end

  defp handle_event(state, %ExRatatui.Event.Key{code: "q"}), do: %{state | quit: true}
  defp handle_event(state, %ExRatatui.Event.Key{code: "Q"}), do: %{state | quit: true}

  defp handle_event(state, %ExRatatui.Event.Key{code: "up"}) do
    %{state | selected: max(0, state.selected - 1)}
  end

  defp handle_event(state, %ExRatatui.Event.Key{code: "down"}) do
    %{state | selected: min(length(state.tasks) - 1, state.selected + 1)}
  end

  defp handle_event(%{running: false} = state, %ExRatatui.Event.Key{code: "enter"}) do
    task = Enum.at(state.tasks, state.selected)
    Runner.start_async(task, self())
    %{state | running: true, current_task: task, log: ["Running: #{task.name}...", ""]}
  end

  defp handle_event(state, _), do: state

  defp collect_output(state) do
    receive do
      {:output_line, line} ->
        log = Enum.take(state.log ++ [line], -1000)
        collect_output(%{state | log: log})

      {:task_done, code} ->
        status = if code == 0, do: "✓ Done", else: "✗ Failed (exit #{code})"
        log = state.log ++ ["", status]
        write_log(state.current_task, log, code)
        %{state | running: false, current_task: nil, log: log}
    after
      0 -> state
    end
  end

  defp write_log(nil, _log, _code), do: :ok

  defp write_log(task, log, code) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    status = if code == 0, do: "ok", else: "fail"
    filename = "#{timestamp}-#{task.name}-#{status}.log"
    path = Path.join(Config.logs_dir(), filename)

    content = Enum.join(log, "\n")
    File.write!(path, content)
  end
end
