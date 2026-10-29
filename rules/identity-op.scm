; Identity operations: x + 0, x - 0, x shl 0, x shr 0, x or 0, x and 0 (right
; operand literal 0) and x * 1, x div 1, x mod 1 (right operand literal 1).
; Detected on exprBinary with a literalNumber right operand; the operator is
; an anonymous token for + - * so it is matched by its TEXT. The literal is
; anchored (^0$ / ^1$) so 10, 100, 0.5 never match.
; Known FP shapes: Byte + 0 used to promote a type; X and 0 / X mod 1 are the
; constant 0 (still flagged -- the operation is pointless either way).
; The fix returns the left operand ({x}); it is bound only where that is the value:
; x and 0 / x mod 1 are the constant 0, so they report without a fix.
((exprBinary
  lhs: (_) @x
  operator: (_) @op
  rhs: (literalNumber) @n) @warn
  (#match? @op "(?i)^(\\+|-|shl|shr|or)$")
  (#match? @n "^0$"))

((exprBinary
  operator: (_) @op
  rhs: (literalNumber) @n) @warn
  (#match? @op "(?i)^and$")
  (#match? @n "^0$"))

((exprBinary
  lhs: (_) @x
  operator: (_) @op
  rhs: (literalNumber) @n) @warn
  (#match? @op "(?i)^(\\*|div)$")
  (#match? @n "^1$"))

((exprBinary
  operator: (_) @op
  rhs: (literalNumber) @n) @warn
  (#match? @op "(?i)^mod$")
  (#match? @n "^1$"))
