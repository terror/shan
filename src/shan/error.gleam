import gleam/int

pub type Error {
  IoError
  HttpError(status: Int, body: String)
  RequestError(String)
  DecodeError(String)
  TokenError(String)
  CredentialError(String)
  MaxIterations
  UsageError
}

pub fn to_string(error: Error) -> String {
  case error {
    IoError -> "failed to read input"
    HttpError(status, body) ->
      "API returned " <> int.to_string(status) <> ": " <> body
    RequestError(msg) -> "failed to connect: " <> msg
    DecodeError(msg) -> "failed to decode response: " <> msg
    TokenError(msg) -> msg
    CredentialError(msg) -> msg
    MaxIterations -> "max iterations reached"
    UsageError ->
      "usage: shan              interactive mode\n       shan -p <prompt>  one-off prompt\n       shan login        authenticate"
  }
}
