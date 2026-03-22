import envoy
import gleam/int
import gleam/io
import shan/api
import shan/auth
import shan/loop
import shan/message
import shellout

pub fn main() -> Nil {
  ensure_started()
  case shellout.arguments() {
    ["login"] -> do_login()
    [prompt, ..] -> do_run(prompt)
    [] -> {
      io.println("usage: shan login")
      io.println("       shan <prompt>")
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

fn do_run(prompt: String) -> Nil {
  let auth = resolve_auth()

  let config =
    api.Config(
      auth:,
      model: "claude-sonnet-4-20250514",
      max_tokens: 4096,
      system: "You are a coding agent. You can read files and run bash commands to help the user with software engineering tasks. Be concise.",
    )

  let messages = [message.user(prompt)]

  case loop.run(config, messages, 10) {
    Ok(_) -> Nil
    Error(loop.ApiError(api.HttpError(status, body))) ->
      io.println("API error (" <> int.to_string(status) <> "): " <> body)
    Error(loop.ApiError(api.RequestError(msg))) ->
      io.println("error: failed to connect to API: " <> msg)
    Error(loop.ApiError(api.DecodeError(msg))) ->
      io.println("error: failed to decode response: " <> msg)
    Error(loop.MaxIterations) -> io.println("error: max iterations reached")
  }
}

fn resolve_auth() -> api.Auth {
  case envoy.get("ANTHROPIC_API_KEY") {
    Ok(key) -> api.ApiKey(key)
    Error(_) ->
      case auth.load_credentials() {
        Ok(creds) ->
          case auth.ensure_valid(creds) {
            Ok(valid_creds) -> api.OAuthToken(valid_creds.access_token)
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
