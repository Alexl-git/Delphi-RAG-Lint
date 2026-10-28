; Delphi 13: `X is not T` replaces `not (X is T)`.
; Matches a unary `not` whose operand is a parenthesised `is` test. Without the
; parentheses `not X is T` binds as `(not X) is T`, so only the parenthesised
; form is the idiom this rule rewrites.
((exprUnary
  operator: (kNot)
  operand: (exprParens
    (exprBinary lhs: (_) @x operator: (kIs) rhs: (_) @t))) @warn)
