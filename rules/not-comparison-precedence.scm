; 'not A = B' parses as '(not A) = B' because 'not' binds tighter than the
; comparison operators -- almost always a bug; write 'not (A = B)'. Only the
; comparison operators are flagged (logical 'not A and B' is intentional).
((exprBinary
  lhs: (exprUnary operator: (kNot))
  operator: [(kEq) (kNeq) (kLt) (kGt)]) @warn)
