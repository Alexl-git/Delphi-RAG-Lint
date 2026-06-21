; Comparing UpperCase(X)/LowerCase(X) to a string literal is fragile and slow:
; it allocates a new string, and it is silently always-false if the literal is not
; in the matching case (e.g. UpperCase(X) = 'abc'). Use SameText (case-insensitive)
; or compare without the conversion.
((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kEq) (kNeq)]
  rhs: (literalString)) @warn
  (#match? @fn "(?i)^(ansi)?(upper|lower)case$"))
