defmodule Typelixir do
  @moduledoc false

  def check(all_paths) do
    modules_paths = ModuleNamesExtractor.extract_modules_names(all_paths)
    states = compile_files(all_paths, [], modules_paths, Map.new())
    Enum.each(states, fn state -> print_state(state) end)
  end

  defp compile_files(paths, results, modules_paths, modules_functions) do
    [head | tail] = paths
    {path, state, data, modules_functions} = compile_file(head, modules_functions)

    if state == :needs_compile do
      new_paths = [modules_paths[data]] ++ Enum.filter(paths, fn e -> e != modules_paths[data] end)
      compile_files(new_paths, results, modules_paths, modules_functions)
    else
      results = results ++ [{path, state, data}]
      case tail do
        [] -> results
        rem_paths -> compile_files(rem_paths, results, modules_paths, modules_functions)
      end
    end
  end

  defp compile_file(path, modules_functions) do
    env = %{
      state: :ok,
      data: [],
      module_name: :empty,
      vars: %{},
      funcs: %{},
      modules_functions: modules_functions
    }
    result = Processor.process_file(path, env)
    {"#{path}", result[:state], result[:data], result[:modules_functions]}
  end

  defp print_state({path, :ok, warnings}) do
    Enum.each(warnings, fn warning -> IO.puts "#{IO.ANSI.yellow()}warning:#{IO.ANSI.white()} #{elem(warning, 1)} \n\s\s#{path}:#{elem(warning, 0)}\n" end)
  end

  defp print_state({path, :error, error}) do
    IO.puts "#{IO.ANSI.red()}error:#{IO.ANSI.white()} #{elem(error, 1)} \n\s\s#{path}:#{elem(error, 0)}\n"
  end
end
