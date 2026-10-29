; Power(X, 2) -> Sqr(X); Power(X, 0.5) -> Sqrt(X); Sqrt(Sqr(A) + Sqr(B)) ->
; Hypot(A, B). Exponent literal must be exactly 2 / 2.0 / 0.5 / .5.
; Known FP shape: Power on Single/Extended where Sqr differs in precision;
; negative X with Power(X, 0.5).
; ORDER MATTERS: when two patterns match one node the first in this file supplies the
; finding (and its fix), so the fix-bound patterns come BEFORE the report-only ones.
; Fix patterns (autofix wave A1): the same Power(X, 2) / Power(X, 0.5) when X is a
; plain identifier declared as a float local/parameter -- Sqr of an Integer would change
; the result type, so every other X stays report-only. Bound captures: @sqx / @srx.
((exprCall
  entity: (identifier) @fn
  args: (exprArgs
    . (identifier) @sqx
    . (literalNumber) @p)) @warn
  (#match? @fn "(?i)^Power$")
  (#match? @p "^(2|2\\.0+)$")
  (#declared-type? @sqx "^(Double|Single|Extended|Real)$"))

((exprCall
  entity: (identifier) @fn
  args: (exprArgs
    . (identifier) @srx
    . (literalNumber) @p)) @warn
  (#match? @fn "(?i)^Power$")
  (#match? @p "^(0?\\.5|0?\\.50*)$")
  (#declared-type? @srx "^(Double|Single|Extended|Real)$"))

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

