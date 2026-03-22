import gleam/dict.{type Dict}
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
