import gleam/json
import shan/message.{type Message, type Response}

pub type SendError {
  RequestError(String)
  HttpError(status: Int, body: String)
  DecodeError(String)
}

pub type Provider =
  fn(List(Message), List(json.Json)) -> Result(Response, SendError)
