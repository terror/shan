import envoy
import gleam/int
import gleam/io
import shan/api
import shan/loop
import shan/message
import shellout

pub fn main() -> Nil {
  let api_key = case envoy.get("ANTHROPIC_API_KEY") {
    Ok(key) -> key
    Error(_) -> {
      io.println("error: ANTHROPIC_API_KEY not set")
      halt(1)
    }
  }

  let config =
    api.Config(
      api_key:,
      model: "claude-sonnet-4-20250514",
      max_tokens: 4096,
      system: "You are a coding agent. You can read files and run bash commands to help the user with software engineering tasks. Be concise.",
    )

  let prompt = case shellout.arguments() {
    [prompt, ..] -> prompt
    [] -> {
      io.println("usage: shan <prompt>")
      halt(1)
    }
  }

  let messages = [message.user(prompt)]

  case loop.run(config, messages, 10) {
    Ok(_) -> Nil
    Error(loop.ApiError(api.HttpError(status, body))) ->
      io.println("API error (" <> int.to_string(status) <> "): " <> body)
    Error(loop.ApiError(api.RequestError)) ->
      io.println("error: failed to connect to API")
    Error(loop.ApiError(api.DecodeError(msg))) ->
      io.println("error: failed to decode response: " <> msg)
    Error(loop.MaxIterations) -> io.println("error: max iterations reached")
  }
}

@external(erlang, "erlang", "halt")
fn do_halt(status: Int) -> Nil

fn halt(status: Int) -> a {
  do_halt(status)
  panic as "unreachable"
}
