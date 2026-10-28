; `X as TObject` is redundant only when X is a CLASS reference. An interface-typed operand
; (`IFoo as TObject` is the only way from an interface to its instance) and an operand whose
; type the source does not show (a field, an undeclared name) are NOT reported: the rule needs
; a declared, non-interface type (declared-type? fails closed on an unknown type).
((exprBinary
  lhs: (identifier) @x
  operator: (kAs)
  rhs: (identifier) @type
  (#eq? @type "TObject")
  (#declared-type? @x "^(?!I[A-Z])."))
  @warn)
