import envoy
import gleam/int
import gleam/io
import shan/anthropic
import shan/auth
import shan/loop
import shan/message
import shan/provider
import shan/tui
import shellout

pub fn main() -> Nil {
  ensure_started()
  case shellout.arguments() {
    ["login"] -> do_login()
    ["-p", prompt, ..] | ["--prompt", prompt, ..] -> do_prompt(prompt)
    [] -> do_tui()
    _ -> {
      io.println("usage: shan              interactive mode")
      io.println("       shan -p <prompt>  one-off prompt")
      io.println("       shan login        authenticate with Claude")
      halt(1)
    }
  }
}

fn do_login() -> Nil {
  case auth.login() {
    Ok(_) -> Nil
    Error(auth.IoError) -> io.println("error: failed to read input")
    Error(auth.HttpError) ->
      io.println("error: failed to connect to auth server")
    Error(auth.TokenError(msg)) -> io.println("error: " <> msg)
    Error(auth.CredentialError(msg)) -> io.println("error: " <> msg)
  }
}

const system_prompt = "You are a coding agent. You can read files and run bash commands to help the user with software engineering tasks. Be concise."

fn do_tui() -> Nil {
  let provider = resolve_provider()
  tui.start(provider)
}

fn do_prompt(prompt: String) -> Nil {
  let provider = resolve_provider()
  let messages = [message.user(prompt)]

  case loop.run(provider, messages, 10, loop.default_render()) {
    Ok(_) -> Nil
    Error(loop.ApiError(provider.HttpError(status, body))) ->
      io.println("API error (" <> int.to_string(status) <> "): " <> body)
    Error(loop.ApiError(provider.RequestError(msg))) ->
      io.println("error: failed to connect to API: " <> msg)
    Error(loop.ApiError(provider.DecodeError(msg))) ->
      io.println("error: failed to decode response: " <> msg)
    Error(loop.MaxIterations) -> io.println("error: max iterations reached")
  }
}

fn resolve_provider() -> provider.Provider {
  let auth = resolve_auth()
  anthropic.provider(auth, "claude-sonnet-4-20250514", 4096, system_prompt)
}

fn resolve_auth() -> anthropic.Auth {
  case envoy.get("ANTHROPIC_API_KEY") {
    Ok(key) -> anthropic.ApiKey(key)
    Error(_) ->
      case auth.load_credentials() {
        Ok(creds) ->
          case auth.ensure_valid(creds) {
            Ok(valid_creds) -> anthropic.OAuthToken(valid_creds.access_token)
            Error(_) -> {
              io.println("error: token refresh failed — run `shan login` again")
              halt(1)
            }
          }
        Error(_) -> {
          io.println(
            "error: no auth configured — set ANTHROPIC_API_KEY or run `shan login`",
          )
          halt(1)
        }
      }
  }
}

@external(erlang, "shan_ffi", "ensure_started")
fn ensure_started() -> Nil

@external(erlang, "erlang", "halt")
fn do_halt(status: Int) -> Nil

fn halt(status: Int) -> a {
  do_halt(status)
  panic as "unreachable"
}
