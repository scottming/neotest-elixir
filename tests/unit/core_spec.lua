local core = require("neotest-elixir.core")

describe("build_iex_test_command", function()
  it("should return the correct command for a test", function()
    local position = {
      type = "test",
      path = "example_test.exs",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed)

    assert.are.equal(
      'ExUnit.configure(output_dir: "test_output"); IExUnit.run("example_test.exs", seed: 1234, line: 2)',
      actual
    )
  end)

  it("should return the correct command for a file", function()
    local position = {
      type = "file",
      path = "test/neotest_elixir/core_spec.exs",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed)

    assert.are.equal(
      'ExUnit.configure(output_dir: "test_output"); IExUnit.run("test/neotest_elixir/core_spec.exs", seed: 1234)',
      actual
    )
  end)

  it("should return the correct command for the folder", function()
    local position = {
      type = "folder",
      path = "test/neotest_elixir",
      range = { 1, 2 },
    }
    local output_dir = "test_output"
    local seed = 1234

    local actual = core.build_iex_test_command(position, output_dir, seed)

    assert.are.equal(
      'ExUnit.configure(output_dir: "test_output"); IExUnit.run("test/neotest_elixir", seed: 1234)',
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
