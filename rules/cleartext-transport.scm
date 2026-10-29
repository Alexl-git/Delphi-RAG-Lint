; Cleartext network transport (CWE-319): an http:// URL passed to an HTTP verb call or
; assigned to .URL / .BaseURL, or TLS explicitly switched off (.UseTLS := utNoTLSSupport).
; Loopback, localhost, 0.0.0.0 and XML namespace URIs (schemas.*, w3.org) are not transport.
; (a) http:// literal as the first argument of .Get/.Post/.Put/.Delete/.Head/.Patch
((exprCall
   entity: (exprDot rhs: (identifier) @verb)
   args: (exprArgs . (literalString) @url)) @warn
  (#any-of? @verb "Get" "Post" "Put" "Delete" "Head" "Patch")
  (#match? @url "(?i)^'http://")
  (#not-match? @url "(?i)localhost|127\\.|::1|0\\.0\\.0\\.0|schemas\\.|w3\\.org"))
; (a) http:// literal assigned to .URL / .BaseURL
((assignment
   lhs: (exprDot rhs: (identifier) @prop)
   rhs: (literalString) @url) @warn
  (#any-of? @prop "URL" "BaseURL")
  (#match? @url "(?i)^'http://")
  (#not-match? @url "(?i)localhost|127\\.|::1|0\\.0\\.0\\.0|schemas\\.|w3\\.org"))
; (b)/(c) .UseTLS := utNoTLSSupport (TIdSMTP / TIdPOP3 / TIdIMAP4 / any Indy client)
((assignment
   lhs: (exprDot rhs: (identifier) @prop)
   rhs: (identifier) @val) @warn
  (#eq? @prop "UseTLS")
  (#eq? @val "utNoTLSSupport"))
