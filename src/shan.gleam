import envoy
import gleam/io
import gleam/result
import shan/anthropic
import shan/anthropic/auth
import shan/bridge
import shan/error
import shan/loop
import shan/message
import shan/provider
import shan/tui
import shellout

const system_prompt = "You are a coding agent. You can read files and run bash commands to help the user with software engineering tasks. Be concise."

fn resolve_provider() -> Result(provider.Provider, error.Error) {
  case envoy.get("ANTHROPIC_API_KEY") {
    Ok(key) ->
      Ok(anthropic.provider(
        anthropic.ApiKey(key),
        "claude-sonnet-4-20250514",
        16_384,
        10_000,
        system_prompt,
      ))
    Error(_) -> {
      use credentials <- result.try(auth.load_credentials())

      Ok(anthropic.provider(
        anthropic.OAuthToken(credentials.access_token),
        "claude-sonnet-4-20250514",
        16_384,
        10_000,
        system_prompt,
      ))
    }
  }
}

fn run() -> Result(Nil, error.Error) {
  case shellout.arguments() {
    ["login"] ->
      auth.login()
      |> result.replace(Nil)
    ["-p", prompt, ..] | ["--prompt", prompt, ..] -> {
      use provider <- result.try(resolve_provider())
      let messages = [message.user(prompt)]
      loop.run(provider, messages, 10, loop.default_render())
      |> result.replace(Nil)
    }
    [] -> {
      use provider <- result.try(resolve_provider())
      tui.start(provider)
      Ok(Nil)
    }
    _ -> Error(error.UsageError)
  }
}

pub fn main() -> Nil {
  bridge.ensure_started()

  case run() {
    Ok(Nil) -> Nil
    Error(e) -> {
      io.println("error: " <> error.to_string(e))
      bridge.halt(1)
    }
  }
}
