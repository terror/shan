import gleam/json
import gleam/list
import shan/message.{type Message, type Response}

pub type ApiError {
  RequestError(String)
  HttpError(status: Int, body: String)
  DecodeError(String)
}

pub type Auth {
  ApiKey(String)
  OAuthToken(String)
}

pub type Config {
  Config(auth: Auth, model: String, max_tokens: Int, system: String)
}

pub fn send(
  config: Config,
  messages: List(Message),
  tools: List(json.Json),
) -> Result(Response, ApiError) {
  let system_value = case config.auth {
    OAuthToken(_) ->
      json.preprocessed_array([
        json.object([
          #("type", json.string("text")),
          #(
            "text",
            json.string(
              "You are Claude Code, Anthropic's official CLI for Claude.",
            ),
          ),
        ]),
        json.object([
          #("type", json.string("text")),
          #("text", json.string(config.system)),
        ]),
      ])
    ApiKey(_) -> json.string(config.system)
  }

  let body =
    json.object([
      #("model", json.string(config.model)),
      #("max_tokens", json.int(config.max_tokens)),
      #("system", system_value),
      #(
        "messages",
        json.preprocessed_array(list.map(messages, message.encode_message)),
      ),
      #("tools", json.preprocessed_array(tools)),
    ])
    |> json.to_string

  let headers = [
    #("anthropic-version", "2023-06-01"),
    ..auth_headers(config.auth)
  ]

  case
    http_post_with_headers(
      "https://api.anthropic.com/v1/messages",
      headers,
      "application/json",
      body,
    )
  {
    Error(msg) -> Error(RequestError(msg))
    Ok(#(200, resp_body)) ->
      case json.parse(resp_body, message.decode_response()) {
        Ok(response) -> Ok(response)
        Error(e) -> Error(DecodeError(json_error_to_string(e)))
      }
    Ok(#(status, resp_body)) -> Error(HttpError(status, resp_body))
  }
}

fn auth_headers(auth: Auth) -> List(#(String, String)) {
  case auth {
    ApiKey(key) -> [#("x-api-key", key)]
    OAuthToken(token) -> [
      #("authorization", "Bearer " <> token),
      #("anthropic-beta", "claude-code-20250219,oauth-2025-04-20"),
      #("user-agent", "claude-cli/1.0.0"),
      #("x-app", "cli"),
      #("anthropic-dangerous-direct-browser-access", "true"),
    ]
  }
}

fn json_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "unexpected end of input"
    json.UnexpectedByte(b) -> "unexpected byte: " <> b
    json.UnexpectedSequence(s) -> "unexpected sequence: " <> s
    json.UnableToDecode(_) -> "unable to decode"
  }
}

@external(erlang, "shan_ffi", "http_post_with_headers")
fn http_post_with_headers(
  url: String,
  headers: List(#(String, String)),
  content_type: String,
  body: String,
) -> Result(#(Int, String), String)
