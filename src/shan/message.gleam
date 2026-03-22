import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option

pub type Role {
  User
  Assistant
}

pub type Message {
  Message(role: Role, content: List(Content))
}

pub type Content {
  Text(String)
  Thinking(thinking: String, signature: String)
  ToolUse(id: String, name: String, input: Dict(String, String))
  ToolResult(id: String, content: String, is_error: Bool)
}

pub type StopReason {
  EndTurn
  ToolUseStop
  MaxTokens
}

pub type Response {
  Response(content: List(Content), stop_reason: StopReason, usage: Usage)
}

pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int)
}

pub fn user(text: String) -> Message {
  Message(role: User, content: [Text(text)])
}

pub fn role_to_string(role: Role) -> String {
  case role {
    User -> "user"
    Assistant -> "assistant"
  }
}

pub fn encode_message(message: Message) -> json.Json {
  json.object([
    #("role", json.string(role_to_string(message.role))),
    #(
      "content",
      json.preprocessed_array(list.map(message.content, encode_content)),
    ),
  ])
}

pub fn encode_content(content: Content) -> json.Json {
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

pub fn decode_response() -> decode.Decoder(Response) {
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

pub fn tool_uses(content: List(Content)) -> List(Content) {
  list.filter(content, fn(c) {
    case c {
      ToolUse(..) -> True
      _ -> False
    }
  })
}

pub fn text_content(content: List(Content)) -> String {
  list.filter_map(content, fn(c) {
    case c {
      Text(t) -> Ok(t)
      _ -> Error(Nil)
    }
  })
  |> list.first
  |> option.from_result
  |> option.unwrap("")
}
