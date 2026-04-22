defmodule MultiplayerFabricDeploy.Planner do
  @moduledoc """
  Uses the Taskweft RECTGTN HTN planner to derive the ordered build pipeline
  from priv/plans/domains/godot_build.jsonld, then maps each planned action
  to a Tasks struct for execution.
  """

  defp domain_path do
    :code.priv_dir(:multiplayer_fabric_deploy)
    |> Path.join("plans/domains/godot_build.jsonld")
  end

  # Maps planner action names → Tasks :id atoms
  @action_task_map %{
    "a_fetch_godot" => :fetch_godot,
    "a_setup_sccache" => :setup_sccache,
    "a_fetch_vulkan_sdk" => :fetch_vulkan_sdk,
    "a_setup_emscripten" => :setup_emscripten,
    "a_build_macos_template" => :build_macos_template,
    "a_build_linux_editor" => :build_linuxbsd_editor,
    "a_build_web_template" => :build_web_template
  }

  @doc """
  Returns `{:ok, [%Tasks{}]}` in planner-derived execution order,
  or `{:error, reason}`.
  """
  def planned_tasks do
    with {:read, {:ok, domain_json}} <- {:read, File.read(domain_path())},
         {:plan, {:ok, plan_json}} <- {:plan, Taskweft.plan(domain_json)},
         {:decode, {:ok, steps}} <- {:decode, Jason.decode(plan_json)} do
      tasks_by_id = Map.new(MultiplayerFabricDeploy.Tasks.all(), &{&1.id, &1})

      ordered =
        steps
        |> Enum.flat_map(fn
          [action | _args] ->
            case Map.fetch(@action_task_map, action) do
              {:ok, task_id} ->
                case Map.fetch(tasks_by_id, task_id) do
                  {:ok, task} -> [task]
                  :error -> []
                end

              :error ->
                []
            end

          _ ->
            []
        end)

      {:ok, ordered}
    else
      {:read, {:error, reason}} -> {:error, "domain read failed: #{inspect(reason)}"}
      {:plan, {:error, reason}} -> {:error, "planner failed: #{reason}"}
      {:decode, {:error, reason}} -> {:error, "plan JSON decode failed: #{inspect(reason)}"}
    end
  end
end
