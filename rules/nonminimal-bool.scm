; 'not (A = B)', 'not (A <> B)' and 'not (A in S)': a negated parenthesised
; equality / inequality / membership. Only these three shapes; not (A < B) is
; deliberately NOT flagged (NaN: not (A < B) is not A >= B for floats), and
; not (X or Y) / not Call(..) are not comparisons.
; not (A in S) is A not in S since Delphi 13 (dcc64 37.0 compiles it; the grammar parses
; 'not in' as one infix operator). Known FP shape: operator-overloaded = on records.
; The fix covers all three (the parentheses stay: =, <> and not in bind looser than
; and/or, so 'C and not (A = B)' needs '(A <> B)').
((exprUnary
  operator: (kNot)
  operand: (exprParens
    (exprBinary lhs: (_) @eql operator: (kEq) rhs: (_) @eqr))) @warn)

((exprUnary
  operator: (kNot)
  operand: (exprParens
    (exprBinary lhs: (_) @nel operator: (kNeq) rhs: (_) @ner))) @warn)

((exprUnary
  operator: (kNot)
  operand: (exprParens
    (exprBinary lhs: (_) @inl operator: (kIn) rhs: (_) @inr))) @warn)
