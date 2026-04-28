import email

pub fn valid_email_is_accepted_test() {
  let assert Ok(e) = email.new("foo@bar.com")
  assert email.to_string(e) == "foo@bar.com"
}

pub fn empty_string_is_rejected_test() {
  assert email.new("") == Error(email.Empty)
}

pub fn whitespace_only_is_rejected_as_empty_test() {
  assert email.new("   ") == Error(email.Empty)
}

pub fn leading_and_trailing_whitespace_is_trimmed_test() {
  let assert Ok(e) = email.new("  foo@bar.com  ")
  assert email.to_string(e) == "foo@bar.com"
}

pub fn tabs_and_newlines_are_trimmed_test() {
  let assert Ok(e) = email.new("\tfoo@bar.com\n")
  assert email.to_string(e) == "foo@bar.com"
}

pub fn missing_at_is_rejected_test() {
  assert email.new("foobar.com") == Error(email.MissingAt)
}

pub fn multiple_at_is_rejected_test() {
  assert email.new("foo@bar@baz.com") == Error(email.TooManyAt)
}

pub fn empty_local_part_is_rejected_test() {
  let assert Error(_) = email.new("@bar.com")
}

pub fn empty_domain_part_is_rejected_test() {
  let assert Error(_) = email.new("foo@")
}

pub fn just_an_at_is_rejected_test() {
  let assert Error(_) = email.new("@")
}
