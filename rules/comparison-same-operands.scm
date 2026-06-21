; Both operands of a comparison are the same identifier (X = X, X < X, ...): the
; result is constant (X = X is always True, X < X always False), so this is
; almost always a typo where one side should have been a different variable.
((exprBinary
  lhs: (identifier) @l
  operator: [(kEq) (kNeq) (kLt) (kGt)]
  rhs: (identifier) @r) @warn
  (#eq? @l @r))
