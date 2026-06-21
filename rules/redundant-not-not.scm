; 'not not X' is a redundant double negation -- just use X.
((exprUnary
  operator: (kNot)
  operand: (exprUnary operator: (kNot))) @warn)
