; Pos(Sub, S) compared with 0 (> 0, <> 0, = 0) is a Contains test; Pos(..) = 1
; is a StartsStr/StartsWith test. Only the plain Pos name is matched.
; Known FP shape: Pos with a 3rd (offset) argument, Pos on non-strings.
((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kGt) (kNeq) (kEq)]
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "1"))
