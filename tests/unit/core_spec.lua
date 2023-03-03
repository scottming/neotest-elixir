local core = require("neotest-elixir.core")

describe("build_iex_test_command", function()
  local relative_to

  before_each(function()
    -- always return the input
    relative_to = function(path)
      return path
    end
  end)

  it("should return the correct command for a test", function()
    -- always return the input

    local position = {
      type = "test",
      path = "example_test.exs",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed, relative_to)

    assert.are.equal('IExUnit.run("example_test.exs", line: 2, seed: 1234, output_dir: "test_output")', actual)
  end)

  it("should return the correct command for a file", function()
    local position = {
      type = "file",
      path = "test/neotest_elixir/core_spec.exs",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed, relative_to)

    assert.are.equal('IExUnit.run("test/neotest_elixir/core_spec.exs", seed: 1234, output_dir: "test_output")', actual)
  end)

  it("should return the correct command for the folder", function()
    local position = {
      type = "folder",
      path = "test/neotest_elixir",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed, relative_to)

    assert.are.equal('IExUnit.run("test/neotest_elixir", seed: 1234, output_dir: "test_output")', actual)
  end)
end)

describe("iex_watch_command", function()
  it("should return the correct command", function()
    local results_path = "results_path"
    local maybe_compile_error_path = "maybe_compile_error_path"
    local seed = 1234

    local actual = core.iex_watch_command(results_path, maybe_compile_error_path, seed)

    assert.are.equal(
      "(tail -n 50 -f results_path maybe_compile_error_path &) | grep -q 1234 && cat maybe_compile_error_path",
      actual
    )
  end)
end)

describe("get_or_create_iex_term", function()
  it("should create a new iex term if none exists", function()
    local actual = core.get_or_create_iex_term(42)
    assert.are.equal(42, actual.id)
  end)
end)

describe("build_mix_command", function()
  it("should return the correct command for a test", function()
    local position = {
      type = "test",
      path = "example_test.exs",
      range = { 1, 2 },
    }

    local mix_task_func = function()
      return "test"
    end
    local extra_formatter_func = function()
      return { "ExUnit.CLIFormatter" }
    end
    local mix_test_args_func = function()
      return {}
    end
    local project_root_func = function()
      return "/fake_user/elixir_demo"
    end

    local actual_tbl =
      core.build_mix_command(position, {}, mix_task_func, extra_formatter_func, mix_test_args_func, project_root_func)

    local expected = string.format(
      "elixir -r %s -r %s -S mix test --formatter NeotestElixir.Formatter --formatter ExUnit.CLIFormatter example_test.exs:2",
      core.json_encoder_path,
      core.exunit_formatter_path
    )
    assert.are.equal(expected, table.concat(actual_tbl, " "))
  end)
end)
