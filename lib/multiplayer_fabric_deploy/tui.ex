defmodule MultiplayerFabricDeploy.Tui do
  alias ExRatatui.Widgets.{Block, List, Paragraph}
  alias ExRatatui.Layout.Rect

  @keybindings " [↑/↓] navigate   [Enter] run   [q] quit"

  def render(terminal, state) do
    {w, h} = ExRatatui.terminal_size()

    list_width = max(div(w * 2, 5), 28)
    log_width = w - list_width
    content_height = h - 3

    task_names = Enum.map(state.tasks, fn t -> t.name end)

    selected_task = Enum.at(state.tasks, state.selected)

    list_title =
      if state.running,
        do: " Tasks (running...) ",
        else: " Tasks "

    task_list = %List{
      items: task_names,
      selected: state.selected,
      highlight_symbol: "> ",
      block: %Block{title: list_title, borders: [:all], border_type: :rounded}
    }

    visible_lines = content_height - 2
    log_lines = Enum.take(state.log, -1000) |> Enum.take(-visible_lines)
    log_text = Enum.join(log_lines, "\n")

    log_widget = %Paragraph{
      text: log_text,
      wrap: false,
      block: %Block{title: " Output ", borders: [:all], border_type: :rounded}
    }

    desc = if selected_task, do: "  #{selected_task.desc}", else: ""
    status_text = desc <> "    " <> @keybindings

    status_bar = %Paragraph{
      text: status_text,
      block: %Block{borders: [:top], border_type: :plain}
    }

    ExRatatui.draw(terminal, [
      {task_list, %Rect{x: 0, y: 0, width: list_width, height: content_height}},
      {log_widget, %Rect{x: list_width, y: 0, width: log_width, height: content_height}},
      {status_bar, %Rect{x: 0, y: content_height, width: w, height: 3}}
    ])
  end
end
