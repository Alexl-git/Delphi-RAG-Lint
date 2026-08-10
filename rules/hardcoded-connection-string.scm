; A connection string embedded in source (typically with credentials) is a
; hardcoded secret (CWE-798) and couples the build to one environment. Load it
; from configuration / a secret store. Matched by connection-string keywords.
;
; TIGHTENED 2026-08-10: a PLACEHOLDER is not a connection string. Both of this
; rule's hits on drag-lint's own source were the CLI describing its own usage --
;
;   Writeln('  drag-lint fb-snapshot --connection "Database=...;User=...;Password=...;DriverID=FB"')
;   ... and the matching 'required' error message
;
; -- i.e. the program TELLING A USER how to supply a connection string was
; reported as embedding one. Any literal whose keyword is immediately followed
; by '...' is documentation, not a secret; a real connection string has a value
; there. This keeps every genuine form (Password=hunter2) firing.
((literalString) @warn
  (#match? @warn "(?i)(password=|pwd=|user id=|uid=|data source=|initial catalog=|server=)")
  (#not-match? @warn "(?i)(password|pwd|uid|user id|data source|initial catalog|server)=\\s*\\.\\.\\."))
