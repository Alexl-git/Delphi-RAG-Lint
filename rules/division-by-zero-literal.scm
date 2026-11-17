; Float division by a literal zero (X / 0, X / 0.0) raises EZeroDivide at runtime.
; v1511 B13: `X div 0` / `X mod 0` are no longer reported -- dcc rejects them at compile time
; (E2098 Division by zero), so a finding was a duplicate of the compiler's own error.
((exprBinary
  operator: [(kFdiv)]
  rhs: (literalNumber) @z) @warn
  (#match? @z "^([$]0+|0+(\\.0*)?)$"))
