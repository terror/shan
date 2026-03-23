import gleam/json
import shan/error.{type Error}
import shan/message.{type Message, type Response}

pub type Provider =
  fn(List(Message), List(json.Json)) -> Result(Response, Error)
