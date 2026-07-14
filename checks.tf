# Advisory: the OAuthForm instruction widget only works when a connection uses OAuth2 auth. Warn
# when the UI offers OAuth but no connection is OAuth2 (a common copy-paste mismatch), without
# failing: a definition may ship ahead of its connections.
check "oauth_ui_matches_auth" {
  assert {
    condition = (
      !anytrue([for s in local.instruction_steps : strcontains(jsonencode(s), "OAuthForm")]) ||
      anytrue([for c in values(var.connections) : c.auth.type == "OAuth2"])
    )
    error_message = "The connector UI includes an OAuthForm instruction but no connection uses OAuth2 auth; the form will not function (advisory)."
  }
}
