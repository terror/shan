import gleam/io
import gleam/list
import shan/api.{type Config}
import shan/message.{
  type Content, type Message, Message, ToolResult, ToolUse, ToolUseStop,
}
import shan/tool

pub type AgentError {
  ApiError(api.ApiError)
  MaxIterations
}

pub fn run(
  config: Config,
  messages: List(Message),
  max_iterations: Int,
) -> Result(List(Message), AgentError) {
  loop(config, messages, max_iterations, 0)
}

fn loop(
  config: Config,
  messages: List(Message),
  max_iterations: Int,
  iteration: Int,
) -> Result(List(Message), AgentError) {
  case iteration >= max_iterations {
    True -> Error(MaxIterations)
    False -> {
      case api.send(config, messages, tool.definitions()) {
        Error(e) -> Error(ApiError(e))
        Ok(response) -> {
          print_response(response.content)

          let assistant_message =
            Message(role: message.Assistant, content: response.content)
          let messages = list.append(messages, [assistant_message])

          case response.stop_reason {
            ToolUseStop -> {
              let tool_results = execute_tools(response.content)
              let tool_message =
                Message(role: message.User, content: tool_results)
              let messages = list.append(messages, [tool_message])
              loop(config, messages, max_iterations, iteration + 1)
            }
            _ -> Ok(messages)
          }
        }
      }
    }
  }
}

fn execute_tools(content: List(Content)) -> List(Content) {
  content
  |> message.tool_uses
  |> list.map(fn(c) {
    case c {
      ToolUse(id:, name:, input:) -> {
        io.println("[tool] " <> name)
        let result = tool.execute(name, input)
        ToolResult(id:, content: result.content, is_error: result.is_error)
      }
      _ -> panic as "unreachable"
    }
  })
}

fn print_response(content: List(Content)) {
  list.each(content, fn(c) {
    case c {
      message.Text(text) -> io.println(text)
      message.ToolUse(name:, ..) -> io.println("[calling " <> name <> "]")
      _ -> Nil
    }
  })
}
