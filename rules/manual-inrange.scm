; (X >= A) and (X <= B), in either operand order and with the bound on either
; side of the comparison: (A <= X) and (X <= B). Inclusive bounds only --
; InRange is inclusive, so strict > / < pairs are not flagged. Both X captures
; must be the same text.
; Known FP shape: X of a type InRange has no overload for (Char, enum, string);
; X with side effects (InRange evaluates it once).
((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kGte) rhs: (_)))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kLte) rhs: (_)))) @warn
  (#eq? @x1 @x2))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kLte) rhs: (_)))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kGte) rhs: (_)))) @warn
  (#eq? @x1 @x2))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) operator: (kLte) rhs: (_) @x1))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kLte) rhs: (_)))) @warn
  (#eq? @x1 @x2))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kLte) rhs: (_)))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) operator: (kLte) rhs: (_) @x2))) @warn
  (#eq? @x1 @x2))
