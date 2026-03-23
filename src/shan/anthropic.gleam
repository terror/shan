import gleam/dynamic/decode
import gleam/json
import gleam/list
import shan/bridge
import shan/error.{DecodeError, HttpError, RequestError}
import shan/message.{
  type Content, type Message, type Response, type StopReason, type Usage,
  EndTurn, MaxTokens, Response, Text, Thinking, ToolResult, ToolUse, ToolUseStop,
  Usage,
}
import shan/provider.{type Provider}

pub type Auth {
  ApiKey(String)
  OAuthToken(String)
}

pub fn provider(
  auth: Auth,
  model: String,
  max_tokens: Int,
  thinking_budget: Int,
  system: String,
) -> Provider {
  fn(messages: List(Message), tools: List(json.Json)) {
    send(auth, model, max_tokens, thinking_budget, system, messages, tools)
  }
}

fn send(
  auth: Auth,
  model: String,
  max_tokens: Int,
  thinking_budget: Int,
  system: String,
  messages: List(Message),
  tools: List(json.Json),
) -> Result(Response, error.Error) {
  let system_value = case auth {
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
          #("text", json.string(system)),
        ]),
      ])
    ApiKey(_) -> json.string(system)
  }

  let thinking = case thinking_budget > 0 {
    True -> [
      #(
        "thinking",
        json.object([
          #("type", json.string("enabled")),
          #("budget_tokens", json.int(thinking_budget)),
        ]),
      ),
    ]
    False -> []
  }

  let body =
    json.object(
      list.flatten([
        [
          #("model", json.string(model)),
          #("max_tokens", json.int(max_tokens)),
          #("system", system_value),
          #(
            "messages",
            json.preprocessed_array(list.map(messages, encode_message)),
          ),
          #("tools", json.preprocessed_array(tools)),
        ],
        thinking,
      ]),
    )
    |> json.to_string

  let headers = [#("anthropic-version", "2023-06-01"), ..auth_headers(auth)]

  case
    bridge.http_post_with_headers(
      "https://api.anthropic.com/v1/messages",
      headers,
      "application/json",
      body,
    )
  {
    Error(msg) -> Error(RequestError(msg))
    Ok(#(200, resp_body)) ->
      case json.parse(resp_body, decode_response()) {
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

fn encode_message(message: Message) -> json.Json {
  json.object([
    #("role", json.string(message.role_to_string(message.role))),
    #(
      "content",
      json.preprocessed_array(list.map(message.content, encode_content)),
    ),
  ])
}

fn encode_content(content: Content) -> json.Json {
  case content {
    Text(text) ->
      json.object([
        #("type", json.string("text")),
        #("text", json.string(text)),
      ])
    Thinking(thinking:, signature:) ->
      json.object([
        #("type", json.string("thinking")),
        #("thinking", json.string(thinking)),
        #("signature", json.string(signature)),
      ])
    ToolUse(id:, name:, input:) ->
      json.object([
        #("type", json.string("tool_use")),
        #("id", json.string(id)),
        #("name", json.string(name)),
        #("input", json.dict(input, fn(k) { k }, json.string)),
      ])
    ToolResult(id:, content:, is_error:) ->
      json.object([
        #("type", json.string("tool_result")),
        #("tool_use_id", json.string(id)),
        #("content", json.string(content)),
        #("is_error", json.bool(is_error)),
      ])
  }
}

fn decode_response() -> decode.Decoder(Response) {
  use content <- decode.field("content", decode.list(decode_content()))
  use stop_reason <- decode.field("stop_reason", decode_stop_reason())
  use usage <- decode.field("usage", decode_usage())
  decode.success(Response(content:, stop_reason:, usage:))
}

fn decode_content() -> decode.Decoder(Content) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "text" -> {
      use text <- decode.field("text", decode.string)
      decode.success(Text(text))
    }
    "thinking" -> {
      use thinking <- decode.field("thinking", decode.string)
      use signature <- decode.field("signature", decode.string)
      decode.success(Thinking(thinking:, signature:))
    }
    "tool_use" -> {
      use id <- decode.field("id", decode.string)
      use name <- decode.field("name", decode.string)
      use input <- decode.field(
        "input",
        decode.dict(decode.string, decode.string),
      )
      decode.success(ToolUse(id:, name:, input:))
    }
    _ -> decode.failure(Text(""), "text, thinking, or tool_use")
  }
}

fn decode_stop_reason() -> decode.Decoder(StopReason) {
  use reason <- decode.then(decode.string)
  case reason {
    "end_turn" -> decode.success(EndTurn)
    "tool_use" -> decode.success(ToolUseStop)
    "max_tokens" -> decode.success(MaxTokens)
    _ -> decode.success(EndTurn)
  }
}

fn decode_usage() -> decode.Decoder(Usage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Usage(input_tokens:, output_tokens:))
}

fn json_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "unexpected end of input"
    json.UnexpectedByte(b) -> "unexpected byte: " <> b
    json.UnexpectedSequence(s) -> "unexpected sequence: " <> s
    json.UnableToDecode(_) -> "unable to decode"
  }
}
