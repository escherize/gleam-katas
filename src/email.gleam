import gleam/string

pub opaque type Email {
  Email(value: String)
}

pub type EmailError {
  Empty
  MissingAt
  TooManyAt
  MissingTextBeforeAt
  MissingTextAfterAt
}

pub fn new(raw: String) -> Result(Email, EmailError) {
  let trimmed = string.trim(raw)
  case string.split(trimmed, "@") {
    [""] -> Error(Empty)
    [_] -> Error(MissingAt)
    ["", _] -> Error(MissingTextBeforeAt)
    [_, ""] -> Error(MissingTextAfterAt)
    [_local, _domain] -> Ok(Email(trimmed))
    _ -> Error(TooManyAt)
  }
}

pub fn to_string(email: Email) -> String {
  email.value
}
