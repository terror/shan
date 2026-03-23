pub type Listener

@external(erlang, "shan_ffi", "accept_callback")
pub fn accept_callback(
  listener: Listener,
  timeout_ms: Int,
) -> Result(#(String, String), String)

@external(erlang, "shan_ffi", "ensure_started")
pub fn ensure_started() -> Nil

@external(erlang, "shan_ffi", "get_home")
pub fn get_home() -> Result(String, Nil)

@external(erlang, "shan_ffi", "get_line")
pub fn get_line(prompt: String) -> Result(String, Nil)

@external(erlang, "erlang", "halt")
pub fn halt(status: Int) -> a

@external(erlang, "shan_ffi", "http_post")
pub fn http_post(
  url: String,
  content_type: String,
  body: String,
) -> Result(#(Int, String), String)

@external(erlang, "shan_ffi", "http_post_with_headers")
pub fn http_post_with_headers(
  url: String,
  headers: List(#(String, String)),
  content_type: String,
  body: String,
) -> Result(#(Int, String), String)

@external(erlang, "shan_ffi", "open_url")
pub fn open_url(url: String) -> Nil

@external(erlang, "shan_ffi", "start_listener")
pub fn start_listener(port: Int) -> Result(Listener, String)

@external(erlang, "shan_ffi", "system_time_seconds")
pub fn system_time_seconds() -> Int
