; A string literal assigned to a variable/field whose name looks like a secret
; (password, token, api key, ...) is a hardcoded credential (CWE-798). Load it
; from configuration or a secret store instead of embedding it in source.
; The empty-string case (clearing the value) is excluded.
((assignment
  lhs: (identifier) @name
  operator: (kAssign)
  rhs: (literalString) @val) @warn
  (#match? @name "(?i)(password|passwd|pwd|secret|apikey|api_key|token|credential)")
  (#not-match? @val "^''$"))
