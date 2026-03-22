import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/string
import gleam/uri
import simplifile

const client_id_encoded = "OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl"

fn client_id() -> String {
  let assert Ok(bits) = bit_array.base64_decode(client_id_encoded)
  let assert Ok(id) = bit_array.to_string(bits)
  id
}

const authorize_url = "https://claude.ai/oauth/authorize"

const token_url = "https://platform.claude.com/v1/oauth/token"

const redirect_uri = "http://localhost:53692/callback"

const callback_port = 53_692

const callback_timeout_ms = 120_000

const scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

pub type Credentials {
  Credentials(access_token: String, refresh_token: String, expires_at: Int)
}

pub type AuthError {
  IoError
  HttpError
  TokenError(String)
  CredentialError(String)
}

pub fn login() -> Result(Credentials, AuthError) {
  let verifier = generate_code_verifier()
  let challenge = generate_code_challenge(verifier)

  let auth_url = build_authorize_url(challenge, verifier)

  case start_listener(callback_port) {
    Error(msg) -> Error(TokenError(msg))
    Ok(listener) -> {
      io.println("Opening browser to authenticate with Claude...")
      io.println("")
      io.println("If the browser doesn't open, visit this URL:")
      io.println(auth_url)
      io.println("")
      io.println("Waiting for authentication...")

      open_url(auth_url)

      case accept_callback(listener, callback_timeout_ms) {
        Error(msg) -> Error(TokenError(msg))
        Ok(#(code, callback_state)) ->
          case callback_state == verifier {
            False -> Error(TokenError("state mismatch — possible CSRF attack"))
            True ->
              case exchange_code(code, verifier) {
                Error(e) -> Error(e)
                Ok(creds) ->
                  case save_credentials(creds) {
                    Error(e) -> Error(e)
                    Ok(_) -> {
                      io.println("Logged in successfully!")
                      Ok(creds)
                    }
                  }
              }
          }
      }
    }
  }
}

pub fn load_credentials() -> Result(Credentials, AuthError) {
  case credentials_path() {
    Error(_) -> Error(CredentialError("could not determine home directory"))
    Ok(path) ->
      case simplifile.read(path) {
        Error(_) ->
          Error(CredentialError("no credentials found — run `shan login` first"))
        Ok(contents) ->
          case json.parse(contents, decode_credentials()) {
            Ok(creds) -> Ok(creds)
            Error(_) ->
              Error(CredentialError(
                "corrupt credentials file — run `shan login` again",
              ))
          }
      }
  }
}

pub fn refresh(creds: Credentials) -> Result(Credentials, AuthError) {
  let body =
    json.object([
      #("grant_type", json.string("refresh_token")),
      #("client_id", json.string(client_id())),
      #("refresh_token", json.string(creds.refresh_token)),
    ])
    |> json.to_string

  case http_post(token_url, "application/json", body) {
    Error(msg) -> Error(TokenError("token refresh failed: " <> msg))
    Ok(#(200, resp_body)) ->
      case json.parse(resp_body, decode_token_response()) {
        Ok(new_creds) ->
          case save_credentials(new_creds) {
            Ok(_) -> Ok(new_creds)
            Error(e) -> Error(e)
          }
        Error(_) -> Error(TokenError("failed to parse refresh response"))
      }
    Ok(#(status, resp_body)) ->
      Error(TokenError(
        "token refresh failed (" <> string.inspect(status) <> "): " <> resp_body,
      ))
  }
}

pub fn ensure_valid(creds: Credentials) -> Result(Credentials, AuthError) {
  let now = current_time_seconds()
  let buffer = 300
  case now >= creds.expires_at - buffer {
    False -> Ok(creds)
    True -> refresh(creds)
  }
}

fn generate_code_verifier() -> String {
  crypto.strong_random_bytes(32)
  |> bit_array.base64_url_encode(False)
}

fn generate_code_challenge(verifier: String) -> String {
  crypto.hash(crypto.Sha256, <<verifier:utf8>>)
  |> bit_array.base64_url_encode(False)
}

fn build_authorize_url(challenge: String, state: String) -> String {
  let query =
    uri.query_to_string([
      #("code", "true"),
      #("client_id", client_id()),
      #("response_type", "code"),
      #("redirect_uri", redirect_uri),
      #("scope", scopes),
      #("code_challenge", challenge),
      #("code_challenge_method", "S256"),
      #("state", state),
    ])
  authorize_url <> "?" <> query
}

fn exchange_code(
  code: String,
  verifier: String,
) -> Result(Credentials, AuthError) {
  let body =
    json.object([
      #("grant_type", json.string("authorization_code")),
      #("client_id", json.string(client_id())),
      #("code", json.string(code)),
      #("state", json.string(verifier)),
      #("redirect_uri", json.string(redirect_uri)),
      #("code_verifier", json.string(verifier)),
    ])
    |> json.to_string

  case http_post(token_url, "application/json", body) {
    Error(msg) -> Error(TokenError("token exchange failed: " <> msg))
    Ok(#(200, resp_body)) ->
      case json.parse(resp_body, decode_token_response()) {
        Ok(creds) -> Ok(creds)
        Error(_) -> Error(TokenError("failed to parse token response"))
      }
    Ok(#(status, resp_body)) ->
      Error(TokenError(
        "token exchange failed ("
        <> string.inspect(status)
        <> "): "
        <> resp_body,
      ))
  }
}

fn decode_token_response() -> decode.Decoder(Credentials) {
  use access_token <- decode.field("access_token", decode.string)
  use refresh_token <- decode.field("refresh_token", decode.string)
  use expires_in <- decode.field("expires_in", decode.int)
  let expires_at = current_time_seconds() + expires_in
  decode.success(Credentials(access_token:, refresh_token:, expires_at:))
}

fn decode_credentials() -> decode.Decoder(Credentials) {
  use access_token <- decode.field("access_token", decode.string)
  use refresh_token <- decode.field("refresh_token", decode.string)
  use expires_at <- decode.field("expires_at", decode.int)
  decode.success(Credentials(access_token:, refresh_token:, expires_at:))
}

fn save_credentials(creds: Credentials) -> Result(Nil, AuthError) {
  case credentials_dir() {
    Error(_) -> Error(CredentialError("could not determine home directory"))
    Ok(dir) -> {
      case simplifile.create_directory_all(dir) {
        Error(_) -> Error(CredentialError("could not create config directory"))
        Ok(_) -> {
          let content =
            json.object([
              #("access_token", json.string(creds.access_token)),
              #("refresh_token", json.string(creds.refresh_token)),
              #("expires_at", json.int(creds.expires_at)),
            ])
            |> json.to_string

          let assert Ok(path) = credentials_path()
          case simplifile.write(path, content) {
            Ok(_) -> Ok(Nil)
            Error(_) ->
              Error(CredentialError("could not write credentials file"))
          }
        }
      }
    }
  }
}

fn credentials_dir() -> Result(String, Nil) {
  case get_home() {
    Ok(home) -> Ok(home <> "/.config/shan")
    Error(_) -> Error(Nil)
  }
}

fn credentials_path() -> Result(String, Nil) {
  case credentials_dir() {
    Ok(dir) -> Ok(dir <> "/credentials.json")
    Error(_) -> Error(Nil)
  }
}

@external(erlang, "shan_ffi", "open_url")
fn open_url(url: String) -> Nil

@external(erlang, "shan_ffi", "get_home")
fn get_home() -> Result(String, Nil)

@external(erlang, "shan_ffi", "system_time_seconds")
fn current_time_seconds() -> Int

pub type Listener

@external(erlang, "shan_ffi", "start_listener")
fn start_listener(port: Int) -> Result(Listener, String)

@external(erlang, "shan_ffi", "accept_callback")
fn accept_callback(
  listener: Listener,
  timeout_ms: Int,
) -> Result(#(String, String), String)

@external(erlang, "shan_ffi", "http_post")
fn http_post(
  url: String,
  content_type: String,
  body: String,
) -> Result(#(Int, String), String)
