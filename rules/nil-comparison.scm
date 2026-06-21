; 'X = nil' / 'X <> nil' work, but 'Assigned(X)' / 'not Assigned(X)' read better
; and are the Delphi idiom (and correct for procedure-of-object references where
; '<> nil' can be subtly wrong). Matches a binary '=' or '<>' against the nil literal.
((exprBinary
  operator: [(kEq) (kNeq)]
  rhs: (kNil)) @warn)
