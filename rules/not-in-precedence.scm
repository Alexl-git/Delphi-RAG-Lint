; 'not X in S' is a precedence trap: it parses as '(not X) in S', NOT
; 'not (X in S)'. This is almost always a bug. Add parentheses.
; Detected: a binary 'in' whose left operand is a 'not' unary expression.
((exprBinary
  lhs: (exprUnary operator: (kNot))
  operator: (kIn)) @warn)
