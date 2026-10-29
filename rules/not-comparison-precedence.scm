; 'not A = B' parses as '(not A) = B' -- almost always a bug; the evident intent is
; 'not (A = B)' (the autofix, tagged risky: it changes the value).
((exprBinary
  lhs: (exprUnary operator: (kNot) operand: (_) @a)
  operator: [(kEq) (kNeq) (kLt) (kGt)] @op
  rhs: (_) @b) @warn)
