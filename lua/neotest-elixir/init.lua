local Path = require("plenary.path")
local async = require("neotest.async")
local lib = require("neotest.lib")
local base = require("neotest-elixir.base")
local logger = require("neotest.logging")
local toggleterm = require("toggleterm")
local toggleterm_terminal = require("toggleterm.terminal")

---@type neotest.Adapter
local ElixirNeotestAdapter = { name = "neotest-elixir" }

local default_formatters = { "NeotestElixir.Formatter" }

local function get_args(_)
  return {}
end

---@param position neotest.Position
---@return string[]
local function get_args_from_position(position)
  local root = ElixirNeotestAdapter.root(position.path)
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

local function get_write_delay()
  return 1000
end

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local function mix_root(file_path)
  return lib.files.match_root_pattern("mix.exs")(file_path)
end

local function get_relative_path(file_path)
  local mix_root_path = mix_root(file_path)
  local root_elems = vim.split(mix_root_path, Path.path.sep)
  local elems = vim.split(file_path, Path.path.sep)
  return table.concat({ unpack(elems, (#root_elems + 1), #elems) }, Path.path.sep)
end

function ElixirNeotestAdapter._generate_id(position, parents)
  if position.dynamic then
    local relative_path = get_relative_path(position.path)
    local line_num = (position.range[1] + 1)
    return (relative_path .. ":" .. line_num)
  else
    return table.concat(
      vim.tbl_flatten({
        position.path,
        vim.tbl_map(function(pos)
          return pos.name
        end, parents),
        position.name,
      }),
      "::"
    )
  end
end

local plugin_path = Path.new(script_path()):parent():parent()
local json_encoder = (plugin_path / "neotest_elixir/json_encoder.ex").filename
local exunit_formatter = (plugin_path / "neotest_elixir/formatter.ex").filename
local mix_interactive_runner = (plugin_path / "neotest_elixir/test_interactive_runner.ex").filename

ElixirNeotestAdapter.root = lib.files.match_root_pattern("mix.exs")

function ElixirNeotestAdapter.filter_dir(_, rel_path, _)
  return rel_path == "test"
    or vim.startswith(rel_path, "test/")
    or rel_path == "apps"
    or rel_path:match("^apps/[^/]+$")
    or rel_path:match("^apps/[^/]+/test")
end

function ElixirNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

local function get_match_type(captured_nodes)
  if captured_nodes["test.name"] then
    return "test"
  end

  if captured_nodes["dytest.name"] then
    return "dytest"
  end

  if captured_nodes["namespace.name"] then
    return "namespace"
  end
end

local match_type_map = {
  test = "test",
  dytest = "test",
  namespace = "namespace",
}

function ElixirNeotestAdapter._build_position(file_path, source, captured_nodes)
  local match_type = get_match_type(captured_nodes)
  if match_type then
    ---@type string
    local name = vim.treesitter.get_node_text(captured_nodes[match_type .. ".name"], source)
    local definition = captured_nodes[match_type .. ".definition"]
    local dynamic = false

    if match_type == "dytest" then
      if vim.startswith(name, "~") then
        name = name:sub(4, #name - 1)
      else
        name = name:gsub('^"', ""):gsub('"$', "")
      end
      dynamic = true
    end

    if vim.startswith(name, "doctest ") then
      dynamic = true
    end

    return {
      type = match_type_map[match_type],
      path = file_path,
      name = name,
      range = { definition:range() },
      dynamic = dynamic,
    }
  end
end

---@async
---@return neotest.Tree | nil
function ElixirNeotestAdapter.discover_positions(path)
  local query = [[
  ;; query
  ;; Describe blocks
  (call
    target: (identifier) @_target (#eq? @_target "describe")
    (arguments . (string (quoted_content) @namespace.name))
    (do_block)
  ) @namespace.definition

  ;; Test blocks (non-dynamic)
  (call
    target: (identifier) @_target (#any-of? @_target "test" "feature" "property")
    (arguments . [
      (string . (quoted_content) @test.name .) ;; Simple string
      (sigil . (sigil_name) @_sigil_name . (quoted_content) @test.name .) (#any-of? @_sigil_name "s" "S") ;; Sigil ~s and ~S, no interpolations
    ]
    )
    (do_block)
  ) @test.definition

  ;; Test blocks (dynamic)
  (call
    target: (identifier) @_target (#any-of? @_target "test" "feature" "property")
    (arguments . [
      (string (interpolation)) ;; String with interpolations
      (identifier) ;; Single variable as name
      (sigil . (sigil_name) @_sigil_name (interpolation)) (#any-of? @_sigil_name "s") ;; Sigil ~s, with interpolations
    ] @dytest.name)
    (do_block)
  ) @dytest.definition

  ;; Doctests
  ;; The word doctest is included in the name to make it easier to notice
  (call
    target: (identifier) @_target (#eq? @_target "doctest")
  ) @test.name @test.definition
  ]]

  local position_id = 'require("neotest-elixir")._generate_id'
  local build_position = 'require("neotest-elixir")._build_position'
  return lib.treesitter.parse_positions(path, query, { position_id = position_id, build_position = build_position })
end

local MAGIC_TERM_NUMBER = 42

local function get_or_create_iex_term()
  -- generate a starting command for the iex terminal
  local function iex_starting_command()
    local json_encoder_path = vim.fn.expand("$HOME/.iex_unit/lib/json_encoder.ex")
    local formatter_path = vim.fn.expand("$HOME/.iex_unit/lib/formatter.ex")
    local runner_path = vim.fn.expand("$HOME/.iex_unit/lib/iex_unit.ex")
    local start_code = "IExUnit.start()"
    --[[ local configuration_code = string.format("ExUnit.configure(output_dir: %q)", output_dir) ]]
    return string.format(
      "MIX_ENV=test iex --no-pry -S mix run -r %q -r %q -r %q -e %q",
      json_encoder_path,
      formatter_path,
      runner_path,
      start_code
    )
  end

  local term = toggleterm_terminal.get(MAGIC_TERM_NUMBER)

  if term == nil then
    toggleterm.exec(iex_starting_command(), MAGIC_TERM_NUMBER, nil, nil, "horizontal")
    term = toggleterm_terminal.get_or_create_term(MAGIC_TERM_NUMBER)
    return term
  else
    return term
  end
end

local function generate_seed()
  local seed_str, _ = string.gsub(vim.fn.reltimestr(vim.fn.reltime()), "(%d+).(%d+)", "%1%2")
  return tonumber(seed_str)
end

local function build_test_command(position, output_dir, seed)
  return string.format("ExUnit.configure(output_dir: %q); IExUnit.run(%q, seed: %s)", output_dir, position.path, seed)
end

local function clear_results_file(results_path)
  local x = io.open(results_path, "w")
  x:write("")
  x:close()
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function ElixirNeotestAdapter.build_spec(args)
  local position = args.tree:data()

  -- custom output dir and use Formatter to write to file
  local output_dir = async.fn.tempname()
  Path:new(output_dir):mkdir()
  local results_path = output_dir .. "/results"

  local term = get_or_create_iex_term()
  local seed = generate_seed()
  test_command = build_test_command(position, output_dir, seed)
  term:send(test_command, true)

  logger.warn("result path: " .. results_path)
  clear_results_file(results_path)

  local stream_data, stop_stream = lib.files.stream_lines(results_path)
  local write_delay = tostring(get_write_delay())
  local watch_command = string.format("( tail -f -n 50 %s & ) | grep -q %s", results_path, seed)

  return {
    command = watch_command,
    context = {
      position = position,
      results_path = results_path,
      stop_stream = stop_stream,
    },
    stream = function()
      return function()
        local lines = stream_data()
        local results = {}
        for _, line in ipairs(lines) do
          local decoded_result = vim.json.decode(line, { luanil = { object = true } })
          local earlier_result = results[decoded_result.id]
          if earlier_result == nil or earlier_result.status ~= "failed" then
            results[decoded_result.id] = {
              status = decoded_result.status,
              output = decoded_result.output,
              errors = decoded_result.errors,
            }
          end
        end
        return results
      end
    end,
    env = {
      NEOTEST_OUTPUT_DIR = output_dir,
      NEOTEST_WRITE_DELAY = write_delay,
      NEOTEST_PLUGIN_PATH = tostring(plugin_path),
    },
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@return neotest.Result[]
function ElixirNeotestAdapter.results(spec, result)
  spec.context.stop_stream()
  local results = {}
  if result.code == 0 or result.code == 2 then
    local data = lib.files.read_lines(spec.context.results_path)

    for _, line in ipairs(data) do
      local decoded_result = vim.json.decode(line, { luanil = { object = true } })
      local earlier_result = results[decoded_result.id]
      if earlier_result == nil or earlier_result.status ~= "failed" then
        results[decoded_result.id] = {
          status = decoded_result.status,
          output = decoded_result.output,
          errors = decoded_result.errors,
        }
      end
    end
  else
    results[spec.context.position.id] = {
      status = "failed",
      output = result.output,
    }
  end

  return results
end

local is_callable = function(obj)
  return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

local function callable_opt(opt)
  if is_callable(opt) then
    return opt
  elseif opt then
    return function()
      return opt
    end
  end
end

setmetatable(ElixirNeotestAdapter, {
  __call = function(_, opts)
    local args = callable_opt(opts.args)
    if args then
      get_args = args
    end

    local write_delay = callable_opt(opts.write_delay)
    if write_delay then
      get_write_delay = write_delay
    end

    return ElixirNeotestAdapter
  end,
})

return ElixirNeotestAdapter
