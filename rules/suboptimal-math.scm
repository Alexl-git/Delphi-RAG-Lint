; Power(X, 2) -> Sqr(X); Power(X, 0.5) -> Sqrt(X); Sqrt(Sqr(A) + Sqr(B)) ->
; Hypot(A, B). Exponent literal must be exactly 2 / 2.0 / 0.5 / .5.
; Known FP shape: Power on Single/Extended where Sqr differs in precision;
; negative X with Power(X, 0.5).
((exprCall
  entity: (identifier) @fn
  args: (exprArgs
    . (_)
    . (literalNumber) @p)) @warn
  (#match? @fn "(?i)^Power$")
  (#match? @p "^(2|2\.0+|0?\.5|0?\.50*)$"))

((exprCall
  entity: (identifier) @fn
  args: (exprArgs
    (exprBinary
      lhs: (exprCall entity: (identifier) @l)
      operator: _ @op
      rhs: (exprCall entity: (identifier) @r)))) @warn
  (#match? @fn "(?i)^Sqrt$")
  (#match? @l "(?i)^Sqr$")
  (#match? @r "(?i)^Sqr$")
  (#eq? @op "+"))
