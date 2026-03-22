import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import shan/message.{
  type Content, type Message, Message, Thinking, ToolResult, ToolUse,
  ToolUseStop,
}
import shan/provider.{type Provider}
import shan/tool

pub type AgentError {
  ApiError(provider.SendError)
  MaxIterations
}

pub type Render {
  Render(
    on_text: fn(String) -> Nil,
    on_thinking: fn(String) -> Nil,
    on_tool_start: fn(String, Dict(String, String)) -> Nil,
    on_tool_done: fn(String, tool.ToolResult) -> Nil,
    on_usage: fn(Int, Int) -> Nil,
  )
}

pub fn default_render() -> Render {
  Render(
    on_text: fn(text) { io.println(text) },
    on_thinking: fn(text) { io.println("[thinking] " <> text) },
    on_tool_start: fn(name, _input) { io.println("[calling " <> name <> "]") },
    on_tool_done: fn(_name, _result) { Nil },
    on_usage: fn(_in, _out) { Nil },
  )
}

pub fn run(
  provider: Provider,
  messages: List(Message),
  max_iterations: Int,
  render: Render,
) -> Result(List(Message), AgentError) {
  loop(provider, messages, max_iterations, 0, render)
}

fn loop(
  provider: Provider,
  messages: List(Message),
  max_iterations: Int,
  iteration: Int,
  render: Render,
) -> Result(List(Message), AgentError) {
  case iteration >= max_iterations {
    True -> Error(MaxIterations)
    False -> {
      case provider(messages, tool.definitions()) {
        Error(e) -> Error(ApiError(e))
        Ok(response) -> {
          print_response(response.content, render)
          { render.on_usage }(
            response.usage.input_tokens,
            response.usage.output_tokens,
          )

          let assistant_message =
            Message(role: message.Assistant, content: response.content)
          let messages = list.append(messages, [assistant_message])

          case response.stop_reason {
            ToolUseStop -> {
              let tool_results = execute_tools(response.content, render)
              let tool_message =
                Message(role: message.User, content: tool_results)
              let messages = list.append(messages, [tool_message])
              loop(provider, messages, max_iterations, iteration + 1, render)
            }
            _ -> Ok(messages)
          }
        }
      }
    }
  }
}

fn execute_tools(content: List(Content), render: Render) -> List(Content) {
  content
  |> message.tool_uses
  |> list.map(fn(c) {
    case c {
      ToolUse(id:, name:, input:) -> {
        { render.on_tool_start }(name, input)
        let result = tool.execute(name, input)
        { render.on_tool_done }(name, result)
        ToolResult(id:, content: result.content, is_error: result.is_error)
      }
      _ -> panic as "unreachable"
    }
  })
}

fn print_response(content: List(Content), render: Render) {
  list.each(content, fn(c) {
    case c {
      Thinking(thinking:, ..) -> { render.on_thinking }(thinking)
      message.Text(text) -> { render.on_text }(text)
      _ -> Nil
    }
  })
}
