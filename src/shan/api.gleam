import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import shan/message.{type Message, type Response}

pub type ApiError {
  RequestError
  HttpError(status: Int, body: String)
  DecodeError(String)
}

pub type Config {
  Config(api_key: String, model: String, max_tokens: Int, system: String)
}

pub fn send(
  config: Config,
  messages: List(Message),
  tools: List(json.Json),
) -> Result(Response, ApiError) {
  let body =
    json.object([
      #("model", json.string(config.model)),
      #("max_tokens", json.int(config.max_tokens)),
      #("system", json.string(config.system)),
      #(
        "messages",
        json.preprocessed_array(list.map(messages, message.encode_message)),
      ),
      #("tools", json.preprocessed_array(tools)),
    ])
    |> json.to_string

  let assert Ok(req) = request.to("https://api.anthropic.com/v1/messages")

  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-api-key", config.api_key)
    |> request.set_header("anthropic-version", "2023-06-01")
    |> request.set_body(body)

  case httpc.send(req) {
    Error(_) -> Error(RequestError)
    Ok(resp) ->
      case resp.status {
        200 ->
          case json.parse(resp.body, message.decode_response()) {
            Ok(response) -> Ok(response)
            Error(e) -> Error(DecodeError(json_error_to_string(e)))
          }
        status -> Error(HttpError(status, resp.body))
      }
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
