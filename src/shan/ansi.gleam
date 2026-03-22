const reset = "\u{001b}[0m"

const bold_code = "\u{001b}[1m"

const dim_code = "\u{001b}[2m"

const italic_code = "\u{001b}[3m"

const cyan_code = "\u{001b}[36m"

const yellow_code = "\u{001b}[33m"

const red_code = "\u{001b}[31m"

const green_code = "\u{001b}[32m"

const magenta_code = "\u{001b}[35m"

const gray_code = "\u{001b}[90m"

pub fn bold(text: String) -> String {
  bold_code <> text <> reset
}

pub fn dim(text: String) -> String {
  dim_code <> text <> reset
}

pub fn italic(text: String) -> String {
  italic_code <> text <> reset
}

pub fn cyan(text: String) -> String {
  cyan_code <> text <> reset
}

pub fn yellow(text: String) -> String {
  yellow_code <> text <> reset
}

pub fn red(text: String) -> String {
  red_code <> text <> reset
}

pub fn green(text: String) -> String {
  green_code <> text <> reset
}

pub fn magenta(text: String) -> String {
  magenta_code <> text <> reset
}

pub fn gray(text: String) -> String {
  gray_code <> text <> reset
}

pub fn bold_cyan(text: String) -> String {
  bold_code <> cyan_code <> text <> reset
}
