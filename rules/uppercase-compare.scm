; Comparing UpperCase(X)/LowerCase(X) to a string literal allocates a new string
; on every evaluation and is slower than SameText, which compares in place.
;
; This rule now covers the STYLE case ONLY: the literal is casable AND its case
; AGREES with the conversion, so the comparison can still match and the fix is a
; straight rewrite to SameText.
;
; Two shapes are deliberately NOT matched here, because lumping all three
; together made a style rule sit on top of a correctness bug:
;
;   * A literal with NO cased characters ('+', '123', ''). UpperCase() is a no-op
;     on it, the comparison is not fragile in any case, and the only cost is a
;     negligible allocation. This used to fire and was pure noise -- it is the
;     "check that the string const is actually casable" case.
;
;   * A literal whose case CONTRADICTS the conversion (UpperCase(X) = 'abc').
;     Those strings can never be equal, so the test is unconditionally false --
;     a defect, not a style nit. uppercase-compare-always-false owns that shape
;     and reports it as an error. Excluded here so it is not double-reported.
;
; Two patterns rather than one because the exclusion is direction-dependent:
; UpperCase must reject a literal containing lowercase, LowerCase the reverse.

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kEq) (kNeq)]
  rhs: (literalString) @lit) @warn
  (#match? @fn "(?i)^(ansi)?uppercase$")
  (#match? @lit "[A-Za-z]")
  (#not-match? @lit "[a-z]"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kEq) (kNeq)]
  rhs: (literalString) @lit) @warn
  (#match? @fn "(?i)^(ansi)?lowercase$")
  (#match? @lit "[A-Za-z]")
  (#not-match? @lit "[A-Z]"))
