; A connection string embedded in source (typically with credentials) is a
; hardcoded secret (CWE-798) and couples the build to one environment. Load it
; from configuration / a secret store. Matched by connection-string keywords.
((literalString) @warn
  (#match? @warn "(?i)(password=|pwd=|user id=|uid=|data source=|initial catalog=|server=)"))
