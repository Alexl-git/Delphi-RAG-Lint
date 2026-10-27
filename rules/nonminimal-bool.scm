; 'not (A = B)', 'not (A <> B)' and 'not (A in S)': a negated parenthesised
; equality / inequality / membership. Only these three shapes; not (A < B) is
; deliberately NOT flagged (NaN: not (A < B) is not A >= B for floats), and
; not (X or Y) / not Call(..) are not comparisons.
; Known FP shape: not (A in S) has no shorter spelling in Delphi (there is no
; 'not in' operator); operator-overloaded = on records.
; The fix covers = and <> only (the parentheses stay: <> and = bind looser than and/or,
; so 'C and not (A = B)' needs '(A <> B)'); the 'in' form has no fix.
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
    (exprBinary operator: (kIn)))) @warn)
