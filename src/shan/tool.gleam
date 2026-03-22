import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/string
import shellout
import simplifile

pub type ToolResult {
  ToolResult(content: String, is_error: Bool)
}

pub fn execute(name: String, input: Dict(String, String)) -> ToolResult {
  case name {
    "read_file" -> execute_read_file(input)
    "write_file" -> execute_write_file(input)
    "list_files" -> execute_list_files(input)
    "edit_file" -> execute_edit_file(input)
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

fn execute_write_file(input: Dict(String, String)) -> ToolResult {
  case dict.get(input, "path"), dict.get(input, "content") {
    Error(_), _ ->
      ToolResult(content: "missing required parameter: path", is_error: True)
    _, Error(_) ->
      ToolResult(content: "missing required parameter: content", is_error: True)
    Ok(path), Ok(content) ->
      case simplifile.write(path, content) {
        Ok(_) -> ToolResult(content: "wrote " <> path, is_error: False)
        Error(_) ->
          ToolResult(content: "failed to write file: " <> path, is_error: True)
      }
  }
}

fn execute_list_files(input: Dict(String, String)) -> ToolResult {
  case dict.get(input, "path") {
    Error(_) ->
      ToolResult(content: "missing required parameter: path", is_error: True)
    Ok(path) ->
      case simplifile.get_files(path) {
        Ok(files) ->
          ToolResult(
            content: files |> list.sort(string.compare) |> string.join("\n"),
            is_error: False,
          )
        Error(_) ->
          ToolResult(
            content: "failed to list files in: " <> path,
            is_error: True,
          )
      }
  }
}

fn execute_edit_file(input: Dict(String, String)) -> ToolResult {
  case
    dict.get(input, "path"),
    dict.get(input, "old_text"),
    dict.get(input, "new_text")
  {
    Error(_), _, _ ->
      ToolResult(content: "missing required parameter: path", is_error: True)
    _, Error(_), _ ->
      ToolResult(
        content: "missing required parameter: old_text",
        is_error: True,
      )
    _, _, Error(_) ->
      ToolResult(
        content: "missing required parameter: new_text",
        is_error: True,
      )
    Ok(path), Ok(old_text), Ok(new_text) ->
      case simplifile.read(path) {
        Error(_) ->
          ToolResult(content: "failed to read file: " <> path, is_error: True)
        Ok(content) ->
          case string.contains(content, old_text) {
            False ->
              ToolResult(content: "old_text not found in file", is_error: True)
            True -> {
              let new_content = string.replace(content, old_text, new_text)

              case simplifile.write(path, new_content) {
                Ok(_) -> ToolResult(content: "edited " <> path, is_error: False)
                Error(_) ->
                  ToolResult(
                    content: "failed to write file: " <> path,
                    is_error: True,
                  )
              }
            }
          }
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
  [
    bash_definition(),
    edit_file_definition(),
    list_files_definition(),
    read_file_definition(),
    write_file_definition(),
  ]
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

fn write_file_definition() -> json.Json {
  json.object([
    #("name", json.string("write_file")),
    #(
      "description",
      json.string(
        "Write content to a file at the given path. Creates the file if it doesn't exist, overwrites if it does.",
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
                  json.string("The absolute path to the file to write"),
                ),
              ]),
            ),
            #(
              "content",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("The content to write to the file"),
                ),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          json.preprocessed_array([
            json.string("path"),
            json.string("content"),
          ]),
        ),
      ]),
    ),
  ])
}

fn list_files_definition() -> json.Json {
  json.object([
    #("name", json.string("list_files")),
    #(
      "description",
      json.string(
        "Recursively list all files in a directory. Returns one file path per line, sorted alphabetically.",
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
                  json.string("The absolute path to the directory to list"),
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

fn edit_file_definition() -> json.Json {
  json.object([
    #("name", json.string("edit_file")),
    #(
      "description",
      json.string(
        "Make a targeted edit to a file by replacing old_text with new_text. More surgical than write_file for making targeted changes. The old_text must match exactly.",
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
                  json.string("The absolute path to the file to edit"),
                ),
              ]),
            ),
            #(
              "old_text",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("The exact text to search for and replace"),
                ),
              ]),
            ),
            #(
              "new_text",
              json.object([
                #("type", json.string("string")),
                #(
                  "description",
                  json.string("The text to replace old_text with"),
                ),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          json.preprocessed_array([
            json.string("path"),
            json.string("old_text"),
            json.string("new_text"),
          ]),
        ),
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
