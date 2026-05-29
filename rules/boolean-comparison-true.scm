; X = True or X = False: redundant boolean comparison
((exprBinary
  operator: (kEq)
  rhs: [(kTrue) (kFalse)])
  @warn)
