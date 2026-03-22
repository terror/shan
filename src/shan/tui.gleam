import gleam/int
import gleam/io
import gleam/list
import gleam/string
import shan/ansi
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
  case get_line(ansi.bold_cyan("❯ ")) {
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
            Error(loop.ApiError(provider.HttpError(status, body))) -> {
              io.println(
                ansi.red("  error")
                <> ansi.dim(
                  " API returned " <> int.to_string(status) <> ": " <> body,
                ),
              )
              io.println("")
              repl(provider, messages)
            }
            Error(loop.ApiError(provider.RequestError(msg))) -> {
              io.println(ansi.red("  error") <> ansi.dim(" " <> msg))
              io.println("")
              repl(provider, messages)
            }
            Error(loop.ApiError(provider.DecodeError(msg))) -> {
              io.println(ansi.red("  error") <> ansi.dim(" decode: " <> msg))
              io.println("")
              repl(provider, messages)
            }
            Error(loop.MaxIterations) -> {
              io.println(ansi.yellow("  ⚠ max iterations reached"))
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
    on_tool_start: fn(name) {
      io.println("  " <> ansi.yellow("●") <> " " <> ansi.dim(name))
    },
    on_tool_done: fn(_name, result) {
      case result.is_error {
        True ->
          io.println(
            "    " <> ansi.red("✗ ") <> ansi.dim(truncate(result.content, 80)),
          )
        False -> Nil
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

fn print_header() -> Nil {
  let bc = "\u{001b}[1;36m"
  let dm = "\u{001b}[2m"
  let rs = "\u{001b}[0m"
  io.println("")
  io.println(bc <> "  ╭─────────────────────────────╮" <> rs)
  io.println(bc <> "  │         shan v1.0.0         │" <> rs)
  io.println(
    bc <> "  │" <> dm <> "    coding agent · gleam     " <> bc <> "│" <> rs,
  )
  io.println(bc <> "  ╰─────────────────────────────╯" <> rs)
  io.println("")
}

fn truncate(text: String, max: Int) -> String {
  case string.length(text) > max {
    True -> string.slice(text, 0, max) <> "…"
    False -> text
  }
}

@external(erlang, "shan_ffi", "get_line")
fn get_line(prompt: String) -> Result(String, Nil)
