; Division or modulo by a literal zero (X div 0, X / 0, X mod 0) always raises
; EZeroDivide / EDivByZero at runtime.
((exprBinary
  operator: [(kDiv) (kFdiv) (kMod)]
  rhs: (literalNumber) @z) @warn
  (#match? @z "^0(\\.0*)?$"))
