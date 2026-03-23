import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import shan/ansi
import shan/bridge
import shan/error
import shan/loop
import shan/message.{type Message}
import shan/provider.{type Provider}

pub fn start(provider: Provider) -> Nil {
  print_header()
  io.println(
    ansi.dim("  Type a prompt to get started. Type ")
    <> ansi.gray("exit")
    <> ansi.dim(" to quit."),
  )
  io.println("")
  repl(provider, [])
}

fn repl(provider: Provider, messages: List(Message)) -> Nil {
  case bridge.get_line(ansi.bold_cyan("❯ ")) {
    Error(_) -> {
      io.println("")
      io.println(ansi.dim("  Goodbye."))
    }
    Ok(input) -> {
      let input = string.trim(input)
      case input {
        "" -> repl(provider, messages)
        "exit" | "quit" -> io.println(ansi.dim("  Goodbye."))
        _ -> {
          io.println("")
          let user_message = message.user(input)
          let messages = list.append(messages, [user_message])

          case loop.run(provider, messages, 20, tui_render()) {
            Ok(updated_messages) -> {
              io.println("")
              repl(provider, updated_messages)
            }
            Error(e) -> {
              io.println(
                ansi.red("  error") <> ansi.dim(" " <> error.to_string(e)),
              )
              io.println("")
              repl(provider, messages)
            }
          }
        }
      }
    }
  }
}

fn tui_render() -> loop.Render {
  loop.Render(
    on_text: fn(text) {
      text
      |> string.split("\n")
      |> list.each(fn(line) { io.println("  " <> line) })
    },
    on_thinking: fn(text) {
      io.println("  " <> ansi.dim("thinking…"))
      text
      |> string.split("\n")
      |> list.each(fn(line) { io.println("  " <> ansi.dim(line)) })
      io.println("")
    },
    on_tool_start: fn(name, input) {
      let detail = case name {
        "read_file" | "write_file" | "list_files" ->
          case dict.get(input, "path") {
            Ok(path) -> " " <> path
            Error(_) -> ""
          }
        "bash" ->
          case dict.get(input, "command") {
            Ok(command) -> " " <> command
            Error(_) -> ""
          }
        _ -> ""
      }
      io.println("  " <> ansi.yellow("●") <> " " <> ansi.dim(name <> detail))
    },
    on_tool_done: fn(name, result) {
      case result.is_error {
        True ->
          io.println(
            "    " <> ansi.red("✗ ") <> ansi.dim(truncate(result.content, 80)),
          )
        False ->
          case name {
            "bash" | "read_file" | "write_file" | "list_files" ->
              result.content
              |> truncate_lines(5)
              |> string.split("\n")
              |> list.each(fn(line) { io.println("    " <> ansi.dim(line)) })
            _ -> Nil
          }
      }
    },
    on_usage: fn(input_tokens, output_tokens) {
      io.println(ansi.gray(
        "  ─── "
        <> int.to_string(input_tokens)
        <> " in · "
        <> int.to_string(output_tokens)
        <> " out ───",
      ))
    },
  )
}

const version = "0.1.0"

fn print_header() -> Nil {
  io.println("")
  io.println("  " <> ansi.bold_cyan("shan") <> " " <> ansi.dim(version))
  io.println("")
}

fn truncate(text: String, max: Int) -> String {
  case string.length(text) > max {
    True -> string.slice(text, 0, max) <> "…"
    False -> text
  }
}

fn truncate_lines(text: String, max: Int) -> String {
  let lines = string.split(text, "\n")
  let total = list.length(lines)
  case total > max {
    True ->
      lines
      |> list.take(max)
      |> string.join("\n")
      |> string.append("\n… " <> int.to_string(total - max) <> " more lines")
    False -> text
  }
}
