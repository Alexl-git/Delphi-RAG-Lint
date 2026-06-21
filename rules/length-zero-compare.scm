; 'Length(X) = 0' / '> 0' reads less clearly than the direct check. For strings use
; X = '' / X <> ''; for dynamic arrays compare Length explicitly only when needed.
((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kEq) (kNeq) (kGt) (kLt)]
  rhs: (literalNumber) @z) @warn
  (#match? @fn "(?i)^length$")
  (#eq? @z "0"))
