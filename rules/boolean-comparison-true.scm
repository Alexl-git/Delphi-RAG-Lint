; X = True / X = False / X <> True / X <> False: redundant boolean comparison.
; Use the boolean directly (or 'not X').
((exprBinary
  operator: [(kEq) (kNeq)]
  rhs: [(kTrue) (kFalse)])
  @warn)
