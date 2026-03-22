import gleam/dict.{type Dict}
import gleam/json
import shellout
import simplifile

pub type ToolResult {
  ToolResult(content: String, is_error: Bool)
}

pub fn execute(name: String, input: Dict(String, String)) -> ToolResult {
  case name {
    "read_file" -> execute_read_file(input)
    "bash" -> execute_bash(input)
    _ -> ToolResult(content: "unknown tool: " <> name, is_error: True)
  }
}

fn execute_read_file(input: Dict(String, String)) -> ToolResult {
  case dict.get(input, "path") {
    Error(_) ->
      ToolResult(content: "missing required parameter: path", is_error: True)
    Ok(path) ->
      case simplifile.read(path) {
        Ok(content) -> ToolResult(content:, is_error: False)
        Error(_) ->
          ToolResult(content: "failed to read file: " <> path, is_error: True)
      }
  }
}

fn execute_bash(input: Dict(String, String)) -> ToolResult {
  case dict.get(input, "command") {
    Error(_) ->
      ToolResult(content: "missing required parameter: command", is_error: True)
    Ok(command) ->
      case shellout.command("sh", ["-c", command], ".", []) {
        Ok(output) -> ToolResult(content: output, is_error: False)
        Error(#(_code, output)) -> ToolResult(content: output, is_error: True)
      }
  }
}

pub fn definitions() -> List(json.Json) {
  [read_file_definition(), bash_definition()]
}

fn read_file_definition() -> json.Json {
  json.object([
    #("name", json.string("read_file")),
    #(
      "description",
      json.string(
        "Read the contents of a file at the given path. Returns the file contents as a string.",
      ),
    ),
    #(
      "input_schema",
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "path",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("The absolute path to the file to read"),
                ),
              ]),
            ),
          ]),
        ),
        #("required", json.preprocessed_array([json.string("path")])),
      ]),
    ),
  ])
}

fn bash_definition() -> json.Json {
  json.object([
    #("name", json.string("bash")),
    #(
      "description",
      json.string(
        "Execute a bash command and return its output. Use this for running shell commands, build tools, git, etc.",
      ),
    ),
    #(
      "input_schema",
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "command",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("The bash command to execute")),
              ]),
            ),
          ]),
        ),
        #("required", json.preprocessed_array([json.string("command")])),
      ]),
    ),
  ])
}
