; A string literal assigned to a variable/field whose name looks like a secret
; (password, api key, ...) is a hardcoded credential (CWE-798). Load it from
; configuration or a secret store instead of embedding it in source.
; The empty-string case (clearing the value) is excluded.
;
; TIGHTENED 2026-08-10, in lockstep with hardcoded-credential-const.scm -- the
; two forms of one rule id must agree on what "looks like a secret" means, or
; the same name fires in a const declaration and not in an assignment.
; See that file's header for the full rationale: bare "token" is dropped (it is
; a LEXICAL token in most real code), and build macros '$(...)' and '...'
; placeholders cannot be secrets.
((assignment
  lhs: (identifier) @name
  operator: (kAssign)
  rhs: (literalString) @val) @warn
  (#match? @name "(?i)(password|passwd|pwd|secret|apikey|api_key|credential|(auth|access|refresh|bearer|session|api)_?token)")
  (#not-match? @val "^''$")
  (#not-match? @val "\\$\\(")
  (#not-match? @val "\\.\\.\\."))
