local lib = require("neotest.lib")
local Path = require("plenary.path")
local toggleterm = require("toggleterm")
local toggleterm_terminal = require("toggleterm.terminal")
local logger = require("neotest.logging")

local M = {}

-- Build the command to send to the IEx shell for running the test
function M.build_iex_test_command(position, output_dir, seed)
  local function get_line_number()
    if position.type == "test" then
      return position.range[1] + 1
    end
  end

  local line_number = get_line_number()
  if line_number then
    return string.format(
      "ExUnit.configure(output_dir: %q); IExUnit.run(%q, seed: %s, line: %s)",
      output_dir,
      position.path,
      seed,
      line_number
    )
  else
    return string.format("ExUnit.configure(output_dir: %q); IExUnit.run(%q, seed: %s)", output_dir, position.path, seed)
  end
end

function M.iex_watch_command(results_path, seed)
  return string.format("( tail -f -n 50 %s & ) | grep -q %s", results_path, seed)
end

local function build_formatters(extra_formatters)
  -- tables need to be copied by value
  local default_formatters = { "NeotestElixir.Formatter" }
  local formatters = { unpack(default_formatters) }
  vim.list_extend(formatters, extra_formatters)

  local result = {}
  for _, formatter in ipairs(formatters) do
    table.insert(result, "--formatter")
    table.insert(result, formatter)
  end

  return result
end

---@param position neotest.Position
---@return string[]
local function build_mix_test_file_args(position, project_root)
  -- Dependency injection for testing
  local root
  if type(project_root) == "function" then
    root = project_root()
  else
    root = lib.files.match_root_pattern("mix.exs")(position.path)
  end

  local path = Path:new(position.path)
  local relative = path:make_relative(root)

  if position.type == "dir" then
    if relative == "." then
      return {}
    else
      return { relative }
    end
  elseif position.type == "file" then
    return { relative }
  else
    local line = position.range[1] + 1
    return { relative .. ":" .. line }
  end
end

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

M.plugin_path = Path.new(script_path()):parent():parent()

-- TODO: dirty version -- make it public only for testing
M.json_encoder_path = (M.plugin_path / "neotest_elixir/json_encoder.ex").filename
M.exunit_formatter_path = (M.plugin_path / "neotest_elixir/formatter.ex").filename
local mix_interactive_runner_path = (M.plugin_path / "neotest_elixir/test_interactive_runner.ex").filename

local function options_for_task(mix_task)
  if mix_task == "test.interactive" then
    return {
      "-r",
      mix_interactive_runner_path,
      "-e",
      "Application.put_env(:mix_test_interactive, :runner, NeotestElixir.TestInteractiveRunner)",
    }
  else
    return {
      "-r",
      M.json_encoder_path,
      "-r",
      M.exunit_formatter_path,
    }
  end
end

function M.build_mix_command(
  position,
  neotest_args,
  mix_task_func,
  extra_formatters_func,
  mix_test_args_func,
  project_root_func
)
  return vim.tbl_flatten({
    {
      "elixir",
    },
    -- deferent tasks have different options
    -- for example, `test.interactive` needs to load a custom runner
    options_for_task(mix_task_func()),
    {
      "-S",
      "mix",
      mix_task_func(), -- `test` is default
    },
    -- default is ExUnit.CLIFormatter
    build_formatters(extra_formatters_func()),
    -- default is {}
    mix_test_args_func(),
    neotest_args.extra_args or {},
    -- test file or directory or testfile:line
    build_mix_test_file_args(position, project_root_func),
  })
end

function M.get_or_create_iex_term(id)
  -- generate a starting command for the iex terminal
  local function iex_starting_command()
    local runner_path = (M.plugin_path / "neotest_elixir/iex-unit/lib/iex_unit.ex").filename
    local start_code = "IExUnit.start()"
    local configuration_code = "ExUnit.configure(formatters: [NeotestElixir.Formatter, ExUnit.CLIFormatter])"
    return string.format(
      "MIX_ENV=test iex --no-pry -S mix run -r %q -r %q -r %q -e %q -e %q",
      M.json_encoder_path,
      M.exunit_formatter_path,
      runner_path,
      start_code,
      configuration_code
    )
  end

  local term = toggleterm_terminal.get(id)

  if term == nil then
    toggleterm.exec(iex_starting_command(), id, nil, nil, "horizontal")
    term = toggleterm_terminal.get_or_create_term(id)
    return term
  else
    return term
  end
end

function M.generate_seed()
  local seed_str, _ = string.gsub(vim.fn.reltimestr(vim.fn.reltime()), "(%d+).(%d+)", "%1%2")
  return tonumber(seed_str)
end

function M.clear_results(results_path)
  local x = io.open(results_path, "w")
  x:write("")
  x:close()
end

return M
