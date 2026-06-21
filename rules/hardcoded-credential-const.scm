; A const initialised to a string literal whose name looks like a secret
; (password, token, api key, ...) bakes a credential into the binary (CWE-798).
; Load it from configuration / a secret store instead. Same rule id as the
; assignment form ('hardcoded-credential').
((declConst
  name: (identifier) @name
  defaultValue: (defaultValue (literalString) @val)) @warn
  (#match? @name "(?i)(password|passwd|pwd|secret|apikey|api_key|token|credential)")
  (#not-match? @val "^''$"))
